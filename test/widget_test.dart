
import 'package:flutter_test/flutter_test.dart';
import 'package:in_class_activity_16/main.dart';

void main() {
  testWidgets('Cloud Quiz app can be created', (tester) async {
    const app = CloudQuizApp();

    expect(app, isA<CloudQuizApp>());
  });
}
