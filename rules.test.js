
const { initializeTestEnvironment, assertSucceeds, assertFails } =
  require('@firebase/rules-unit-testing');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { Timestamp, serverTimestamp } = require('firebase/firestore');

const projectId = 'in-class-activity-16-1e5e3';

function validAttempt() {
  return {
    schemaVersion: 1,
    variant: 'A',
    categoryId: 9,
    questionCount: 10,
    correctCount: 6,
    submittedAt: serverTimestamp(),
  };
}

test('Firestore Security Rules', async (t) => {
  const env = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: readFileSync('firestore.rules', 'utf8'),
    },
  });

  try {
    await env.clearFirestore();

    const alice = env.authenticatedContext('alice').firestore();
    const bob = env.authenticatedContext('bob').firestore();

    const doc = alice.doc('users/alice/attempts/round1');

    await t.test('Owner can create a valid attempt', async () => {
      await assertSucceeds(doc.set(validAttempt()));
    });

    await t.test('Owner can read their attempt', async () => {
      await assertSucceeds(doc.get());
    });

    await t.test('Other user cannot read the attempt', async () => {
      await assertFails(bob.doc('users/alice/attempts/round1').get());
    });

    await t.test('Other user cannot create an attempt', async () => {
      await assertFails(
        bob.doc('users/alice/attempts/round2').set(validAttempt())
      );
    });

    await t.test('Invalid score is rejected', async () => {
      await assertFails(
        alice.doc('users/alice/attempts/round3').set({
          ...validAttempt(),
          correctCount: 11,
        })
      );
    });

    await t.test('Extra fields are rejected', async () => {
      await assertFails(
        alice.doc('users/alice/attempts/round4').set({
          ...validAttempt(),
          extraField: 'not allowed',
        })
      );
    });

    await t.test('Owner cannot update an attempt', async () => {
      await assertFails(doc.update({ correctCount: 10 }));
    });

    await t.test('Owner cannot delete an attempt', async () => {
      await assertFails(doc.delete());
    });
  } finally {
    await env.cleanup();
  }
});
