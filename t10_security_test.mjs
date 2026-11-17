
import { initializeApp } from 'firebase/app';
import {
  getAuth,
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';
import {
  getFirestore,
  doc,
  getDocFromServer,
  setDoc,
  serverTimestamp,
} from 'firebase/firestore';
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';

const rl = createInterface({ input: stdin, output: stdout });

try {
  const apiKey = (await rl.question('Firebase Web API key: ')).trim();
  const projectId = (await rl.question('Firebase project ID: ')).trim();
  const userAUid = (await rl.question('User A UID: ')).trim();
  const emailB = (await rl.question('User B email: ')).trim();
  const passwordB = await rl.question('User B password: ');

  const app = initializeApp({
    apiKey,
    authDomain: `${projectId}.firebaseapp.com`,
    projectId,
  });

  const auth = getAuth(app);
  const db = getFirestore(app);

  const credential = await signInWithEmailAndPassword(
    auth,
    emailB,
    passwordB,
  );

  if (credential.user.uid === userAUid) {
    throw new Error('User A and User B must have different UIDs.');
  }

  const path = `users/${userAUid}/attempts`;
  const testId = `t10-${Date.now()}`;

  async function checkDenied(label, action) {
    try {
      await action();
      console.log(`${label}: FAIL - unexpectedly allowed`);
    } catch (error) {
      if (error.code === 'permission-denied') {
        console.log(`${label}: PASS - permission-denied`);
      } else {
        console.log(`${label}: INCONCLUSIVE - ${error.code ?? error.message}`);
      }
    }
  }

  await checkDenied('T10 READ', () =>
    getDocFromServer(doc(db, path, testId))
  );

  await checkDenied('T10 WRITE', () =>
    setDoc(doc(db, path, `${testId}-write`), {
      schemaVersion: 1,
      variant: 'A',
      categoryId: 9,
      questionCount: 10,
      correctCount: 5,
      submittedAt: serverTimestamp(),
    })
  );

  await signOut(auth);
} catch (error) {
  console.error('TEST ERROR:', error.code ?? error.message);
} finally {
  rl.close();
  process.exit(0);
}
