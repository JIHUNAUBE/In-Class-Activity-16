
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:http/http.dart' as http;

class QuizQuestion {
  final String question;
  final String correctAnswer;
  final List<String> choices;

  QuizQuestion({
    required this.question,
    required this.correctAnswer,
    required this.choices,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final decode = HtmlUnescape().convert;

    if (json['category'] != 'General Knowledge' ||
        json['difficulty'] != 'easy' ||
        json['type'] != 'multiple') {
      throw const FormatException('Invalid question category or type.');
    }

    final rawIncorrect = json['incorrect_answers'];

    if (rawIncorrect is! List || rawIncorrect.length != 3) {
      throw const FormatException('Invalid answer count.');
    }

    if (json['question'] is! String ||
        json['correct_answer'] is! String ||
        !rawIncorrect.every((answer) => answer is String)) {
      throw const FormatException('Invalid question data.');
    }

    final question = decode(json['question'] as String).trim();
    final correct = decode(json['correct_answer'] as String).trim();

    final incorrect = rawIncorrect
        .cast<String>()
        .map((answer) => decode(answer).trim())
        .toList();

    final choices = [correct, ...incorrect];

    if (question.isEmpty ||
        choices.any((answer) => answer.isEmpty) ||
        choices.toSet().length != 4) {
      throw const FormatException('Empty or duplicate answers.');
    }

    choices.shuffle();

    return QuizQuestion(
      question: question,
      correctAnswer: correct,
      choices: choices,
    );
  }
}

class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  static const apiUrl =
      'https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple';

  final List<QuizQuestion> questions = [];
  final List<String> selections = [];

  int currentIndex = 0;
  int score = 0;

  bool isLoading = true;
  bool isFinished = false;
  bool isSaving = false;
  bool isSaved = false;

  String? errorMessage;
  String? saveMessage;
  DateTime? lastRequestAt;
  String? roundId;

  @override
  void initState() {
    super.initState();
    loadQuestions();
  }

  Future<void> loadQuestions() async {
    if (isSaving) return;

    if (lastRequestAt != null &&
        DateTime.now().difference(lastRequestAt!) <
            const Duration(seconds: 5)) {
      setState(() {
        errorMessage = 'Please wait 5 seconds before retrying.';
        isLoading = false;
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    lastRequestAt = DateTime.now();

    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('HTTP error: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic> ||
          decoded['response_code'] != 0 ||
          decoded['results'] is! List ||
          (decoded['results'] as List).length != 10) {
        throw const FormatException('Invalid API response.');
      }

      final loaded = (decoded['results'] as List).map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid question format.');
        }

        return QuizQuestion.fromJson(item);
      }).toList();

      if (!mounted) return;

      setState(() {
        questions
          ..clear()
          ..addAll(loaded);

        selections.clear();
        currentIndex = 0;
        score = 0;
        isFinished = false;
        isLoading = false;
        isSaved = false;
        saveMessage = null;

        // Create one document ID for this quiz round.
        roundId = FirebaseFirestore.instance
            .collection('users')
            .doc()
            .id;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Unable to load questions: $e';
        isLoading = false;
      });
    }
  }

  void selectAnswer(String answer) {
    if (isFinished ||
        currentIndex >= questions.length ||
        selections.length != currentIndex) {
      return;
    }

    setState(() {
      selections.add(answer);

      if (answer == questions[currentIndex].correctAnswer) {
        score++;
      }
    });
  }

  void nextQuestion() {
    if (selections.length <= currentIndex) return;

    if (currentIndex == 9) {
      setState(() {
        isFinished = true;
      });

      saveQuizResult();
    } else {
      setState(() {
        currentIndex++;
      });
    }
  }

  Future<void> saveQuizResult() async {
    if (isSaving ||
        isSaved ||
        !isFinished ||
        selections.length != 10 ||
        roundId == null) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        saveMessage = 'Please sign in again.';
      });
      return;
    }

    setState(() {
      isSaving = true;
      saveMessage = null;
    });

    try {
      final document = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('attempts')
          .doc(roundId);

      await document.set({
        'schemaVersion': 1,
        'variant': 'A',
        'categoryId': 9,
        'questionCount': 10,
        'correctCount': score,
        'submittedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      setState(() {
        isSaved = true;
        saveMessage = 'Result saved to Firestore!';
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;

      // A lost connection can leave the write outcome uncertain.
      // Check whether the document already exists on the server.
      try {
        final document = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('attempts')
            .doc(roundId)
            .get(const GetOptions(source: Source.server));

        if (!mounted) return;

        if (document.exists) {
          setState(() {
            isSaved = true;
            saveMessage = 'Result saved to Firestore!';
          });
          return;
        }
      } catch (_) {
        // Keep the same round ID for a possible retry.
      }

      if (!mounted) return;

      setState(() {
        saveMessage = 'Save failed: ${e.code}';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        saveMessage = 'Unable to confirm save. Please retry.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('General Knowledge Quiz'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: buildContent(),
          ),
        ),
      ),
    );
  }

  Widget buildContent() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (errorMessage != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 56,
            color: Colors.red,
          ),
          const SizedBox(height: 12),
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: loadQuestions,
            child: const Text('Try Again'),
          ),
        ],
      );
    }

    if (isFinished) {
      return buildResults();
    }

    final question = questions[currentIndex];
    final answered = selections.length > currentIndex;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: (currentIndex + 1) / 10,
          ),
          const SizedBox(height: 20),
          Text(
            'Question ${currentIndex + 1} of 10',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 16),
          Text(
            question.question,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),

          // Answer choices
          ...question.choices.map((choice) {
            final isCorrect =
                choice == question.correctAnswer;

            final isSelected = answered &&
                selections[currentIndex] == choice;

            Color? background;

            if (answered) {
              if (isCorrect) {
                background = Colors.green.shade100;
              } else if (isSelected) {
                background = Colors.red.shade100;
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: background,
                  disabledBackgroundColor: background,
                  padding: const EdgeInsets.all(16),
                ),
                onPressed: answered
                    ? null
                    : () => selectAnswer(choice),
                child: Text(choice),
              ),
            );
          }),

          if (answered) ...[
            const SizedBox(height: 12),
            Text(
              selections[currentIndex] ==
                      question.correctAnswer
                  ? 'Correct!'
                  : 'Incorrect! Correct answer: '
                      '${question.correctAnswer}',
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: answered ? nextQuestion : null,
            child: Text(
              currentIndex == 9 ? 'Finish' : 'Next',
            ),
          ),
        ],
      ),
    );
  }

  Widget buildResults() {
    return ListView(
      children: [
        const Icon(
          Icons.emoji_events,
          size: 64,
          color: Colors.teal,
        ),
        const SizedBox(height: 12),
        Text(
          'Final Score: $score / 10',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Firestore save status
        if (isSaving)
          const Center(
            child: CircularProgressIndicator(),
          ),

        if (saveMessage != null)
          Text(
            saveMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSaved ? Colors.green : Colors.red,
            ),
          ),

        if (!isSaving && !isSaved)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ElevatedButton(
              onPressed: saveQuizResult,
              child: const Text('Retry Save'),
            ),
          ),

        const SizedBox(height: 20),
        const Text(
          'Answer Review',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Review all answers
        for (int i = 0; i < questions.length; i++)
          Card(
            child: ListTile(
              title: Text(
                '${i + 1}. ${questions[i].question}',
              ),
              subtitle: Text(
                'Your answer: ${selections[i]}\n'
                'Correct answer: '
                '${questions[i].correctAnswer}',
              ),
              trailing: Icon(
                selections[i] ==
                        questions[i].correctAnswer
                    ? Icons.check_circle
                    : Icons.cancel,
                color: selections[i] ==
                        questions[i].correctAnswer
                    ? Colors.green
                    : Colors.red,
              ),
            ),
          ),

        const SizedBox(height: 16),

        ElevatedButton(
          onPressed: isSaving || !isSaved
              ? null
              : loadQuestions,
          child: const Text('Replay'),
        ),
      ],
    );
  }
}
