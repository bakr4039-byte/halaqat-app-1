import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { db, admin } from "./admin";

// A non-sensitive revision on the school document invalidates all connected
// clients, including legacy incentive documents without a teacherId field.
// The parent path is outside the trigger, so this cannot trigger itself.
export const syncSchoolRevision = onDocumentWritten(
  "circles/{circleId}/{collection}/{documentId}",
  async (event) => {
    const ref = db.collection("circles").doc(event.params.circleId);
    await db.runTransaction(async (tx) => {
      const school = await tx.get(ref);
      if (school.exists) tx.update(ref, { lastDataChange: admin.firestore.FieldValue.serverTimestamp() });
    });
  },
);
