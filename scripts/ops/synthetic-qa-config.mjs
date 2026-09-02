/**
 * Canonical synthetic QA persona structure. No emails, passwords, or keys.
 */

export const PURPOSE = "formative-smoke-test";

export const PERSONAS = [
  {
    persona: "UNIT3_TEST_LEARNER",
    studentNumber: "QA-UNIT3",
    displayName: "Synthetic Unit 3 Learner",
    groupCode: "CYBER-TEST-QA",
    smokeActivityKey: "week2-malware-symptoms",
    emailEnv: ["UNIT3_TEST_EMAIL", "SYNTHETIC_QA_EMAIL_UNIT3"],
    passwordEnv: ["UNIT3_TEST_PASSWORD", "SYNTHETIC_QA_PASSWORD_UNIT3"]
  },
  {
    persona: "TLEVEL_TEST_LEARNER",
    studentNumber: "QA-TLEVEL",
    displayName: "Synthetic T Level Learner",
    groupCode: "TLEVEL-TEST-A",
    smokeActivityKey: "week-1-lesson-1-retrieval",
    emailEnv: ["TLEVEL_TEST_EMAIL", "SYNTHETIC_QA_EMAIL_TLEVEL"],
    passwordEnv: ["TLEVEL_TEST_PASSWORD", "SYNTHETIC_QA_PASSWORD_TLEVEL"]
  },
  {
    persona: "UNIT14_TEST_LEARNER",
    studentNumber: "QA-UNIT14",
    displayName: "Synthetic Unit 14 Learner",
    groupCode: "UNIT14-TEST-A",
    smokeActivityKey: "week-1-variables-and-data-types",
    emailEnv: ["UNIT14_TEST_EMAIL", "SYNTHETIC_QA_EMAIL_UNIT14"],
    passwordEnv: ["UNIT14_TEST_PASSWORD", "SYNTHETIC_QA_PASSWORD_UNIT14"]
  },
  {
    persona: "L2E_TEST_LEARNER",
    studentNumber: "QA-L2E",
    displayName: "Synthetic L2E Learner",
    groupCode: "L2E-TEST-A",
    smokeActivityKey: "week-1-knowledge-check",
    smokeActivityKeys: [
      "week-1-welcome",
      "week-1-digital-technology",
      "week-1-current-emerging",
      "week-1-mobile",
      "week-1-intelligent-computing",
      "week-1-iot",
      "week-1-cloud",
      "week-1-industry",
      "week-1-knowledge-check",
      "week-1-exit-ticket"
    ],
    emailEnv: ["L2E_TEST_EMAIL", "SYNTHETIC_QA_EMAIL_L2E"],
    passwordEnv: ["L2E_TEST_PASSWORD", "SYNTHETIC_QA_PASSWORD_L2E"]
  }
];
