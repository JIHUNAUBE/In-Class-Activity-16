
import { initializeApp } from 'firebase/app';
import {
  getAuth,
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';
import {
  getFirestore,
  doc,
  setDoc,
  updateDoc,
  getDocFromServer,
  serverTimestamp,
} from 'firebase/firestore';
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';

const rl = createInterface({ input: stdin, output: stdout });

try {
  const apiKey = (await rl.question('Firebase Web API key: ')).trim();
  const projectId = (await rl.question('Firebase project ID: ')).trim();
  const emailA = (await rl.question('User A email: ')).trim();
  const passwordA = await rl.question('User A password: ');
  const existingRoundId = (
    await rl.question('Existing User A round ID: ')
  ).trim();

  const app = initializeApp({
    apiKey,
    authDomain: `${projectId}.firebaseapp.com`,
    projectId,
  });

  const auth = getAuth(app);
  const db = getFirestore(app);

  const credential = await signInWithEmailAndPassword(
    auth, emailA, passwordA
  );
  const uid = credential.user.uid;
  console.log('Logged-in UID:', uid);
  const attempts = `users/${uid}/attempts`;

  const existingRef = doc(db, attempts, existingRoundId);
  const before = await getDocFromServer(existingRef);

  if (!before.exists()) {
    throw new Error('Existing round not found. Check the round ID.');
  }

  const original = before.data();

  function validAttempt(score = 5) {
    return {
      schemaVersion: 1,
      variant: 'A',
      categoryId: 9,
      questionCount: 10,
      correctCount: score,
      submittedAt: serverTimestamp(),
    };
  }

  async function expectDenied(label, action) {
    try {
      await action();
      console.log(`${label}: FAIL - unexpectedly allowed`);
    } catch (error) {
      if (error.code === 'permission-denied') {
        console.log(`${label}: PASS - permission-denied`);
      } else {
        console.log(
          `${label}: INCONCLUSIVE - ${error.code ?? error.message}`
        );
      }
    }
  }

  const testPrefix = `t11-${Date.now()}`;

  await expectDenied('T11 SCORE 11', () =>
    setDoc(doc(db, attempts, `${testPrefix}-score`), validAttempt(11))
  );

  await expectDenied('T11 EXTRA FIELD', () =>
    setDoc(doc(db, attempts, `${testPrefix}-extra`), {
      ...validAttempt(),
      extraField: 'not allowed',
    })
  );

  await expectDenied('T11 UPDATE', () =>
    updateDoc(existingRef, { correctCount: 9 })
  );

  const after = await getDocFromServer(existingRef);
  const unchanged =
    after.exists() &&
    after.data().correctCount === original.correctCount &&
    after.data().questionCount === original.questionCount &&
    after.data().submittedAt.toMillis() ===
      original.submittedAt.toMillis();

  console.log(
    `T11 ORIGINAL UNCHANGED: ${unchanged ? 'PASS' : 'FAIL'}`
  );

  await signOut(auth);
} catch (error) {
  console.error('TEST ERROR:', error.code ?? error.message);
} finally {
  rl.close();
  process.exit(0);
}
