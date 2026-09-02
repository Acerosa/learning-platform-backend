import assert from "node:assert/strict";
import test from "node:test";
import { PERSONAS } from "../synthetic-qa-config.mjs";
import {
  collectMissingEnv,
  inspectAuthMetadata,
  isPrivilegedAppMetadata,
  maskEmail,
  resolvePersonaSecrets,
  runProvision
} from "../synthetic-qa-provision.mjs";

const BASE_ENV = {
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "service-role-secret-value",
  UNIT3_TEST_EMAIL: "qa+unit3@example.test",
  UNIT3_TEST_PASSWORD: "unit3-password-value",
  TLEVEL_TEST_EMAIL: "qa+tlevel@example.test",
  TLEVEL_TEST_PASSWORD: "tlevel-password-value",
  UNIT14_TEST_EMAIL: "qa+unit14@example.test",
  UNIT14_TEST_PASSWORD: "unit14-password-value",
  L2E_TEST_EMAIL: "qa+l2e@example.test",
  L2E_TEST_PASSWORD: "l2e-password-value"
};

function secretValues(env = BASE_ENV) {
  return [
    env.SUPABASE_SERVICE_ROLE_KEY,
    env.UNIT3_TEST_EMAIL,
    env.UNIT3_TEST_PASSWORD,
    env.TLEVEL_TEST_EMAIL,
    env.TLEVEL_TEST_PASSWORD,
    env.UNIT14_TEST_EMAIL,
    env.UNIT14_TEST_PASSWORD,
    env.L2E_TEST_EMAIL,
    env.L2E_TEST_PASSWORD
  ];
}

function defaultAssignments() {
  return PERSONAS.map((persona) => ({
    active: true,
    activity_versions: {
      version: persona.smokeActivityKey === "week2-malware-symptoms" ? "1.1.0" : "0.1.0",
      published_at: "2026-01-01T00:00:00Z",
      retired_at: null,
      activities: { stable_key: persona.smokeActivityKey }
    },
    groups: { code: persona.groupCode }
  }));
}

function createHarness({ users = [], students = [], teachers = [], enrolments = [], assignments } = {}) {
  const state = {
    users: [...users],
    students: [...students],
    teachers: [...teachers],
    enrolments: [...enrolments],
    assignments: assignments ? [...assignments] : defaultAssignments(),
    passwordUpdates: 0,
    createCalls: 0,
    rpcCalls: [],
    selectCalls: []
  };

  const admin = {
    async findUserByEmail(email) {
      return state.users.find((user) => String(user.email).toLowerCase() === String(email).toLowerCase()) || null;
    },
    async createUser({ email, password, persona }) {
      state.createCalls += 1;
      const user = {
        id: `00000000-0000-4000-8000-00000000000${state.createCalls}`,
        email,
        email_confirmed_at: "2026-09-02T00:00:00Z",
        user_metadata: { synthetic: true, purpose: "formative-smoke-test", persona },
        app_metadata: { provider: "email" },
        password
      };
      state.users.push(user);
      return user;
    },
    async updatePassword() {
      state.passwordUpdates += 1;
    }
  };

  const rest = {
    async select(schema, table) {
      state.selectCalls.push({ schema, table });
      throw new Error(`direct REST access to ${schema}.${table} is forbidden`);
    },
    async rpc(name, args) {
      state.rpcCalls.push({ name, args });
      if (name === "inspect_synthetic_qa_learners") {
        return PERSONAS.map((persona) => {
          const student = state.students.find((row) => row.student_number === persona.studentNumber);
          const enrolmentCodes = student
            ? state.enrolments
              .filter((row) => row.student_id === student.id && row.status === "active")
              .map((row) => row.groups.code)
            : [];
          const assignment = state.assignments.find((row) => (
            row.groups?.code === persona.groupCode
            && row.active
            && row.activity_versions?.activities?.stable_key === persona.smokeActivityKey
            && row.activity_versions?.published_at
            && row.activity_versions?.retired_at == null
          ));
          return {
            persona: persona.persona,
            student_number: persona.studentNumber,
            display_name: persona.displayName,
            group_code: persona.groupCode,
            smoke_activity_key: persona.smokeActivityKey,
            student_present: Boolean(student),
            student_active: student?.active ?? null,
            is_synthetic: student?.is_synthetic ?? null,
            synthetic_purpose: student?.synthetic_purpose ?? null,
            contact_email_copied: student ? student.contact_email != null : false,
            linked_auth_user_id: student?.auth_user_id ?? null,
            enrolment_codes: enrolmentCodes,
            smoke_assigned: Boolean(assignment),
            smoke_version: assignment?.activity_versions?.version ?? null
          };
        });
      }
      if (name === "inspect_synthetic_qa_auth_user") {
        const student = state.students.find((row) => row.auth_user_id === args.p_auth_user_id);
        return [{
          auth_user_linked: Boolean(student),
          student_number: student?.student_number ?? null,
          is_synthetic: student?.is_synthetic ?? null,
          student_active: student?.active ?? null,
          teacher_linked: state.teachers.some((row) => row.auth_user_id === args.p_auth_user_id)
        }];
      }
      if (name === "ensure_synthetic_qa_groups") {
        return PERSONAS.map((persona) => ({
          persona: persona.persona,
          group_code: persona.groupCode,
          created_or_reused: "reused",
          assignment_count: 1
        }));
      }
      if (name === "provision_synthetic_qa_learner") {
        const persona = PERSONAS.find((item) => item.persona === args.p_persona);
        const existing = state.students.find((row) => row.student_number === persona.studentNumber);
        const student = existing || {
          id: `student-${persona.studentNumber}`,
          student_number: persona.studentNumber,
          display_name: persona.displayName,
          auth_user_id: args.p_auth_user_id,
          active: true,
          is_synthetic: true,
          synthetic_purpose: "formative-smoke-test",
          contact_email: null
        };
        if (!existing) state.students.push(student);
        else student.auth_user_id = args.p_auth_user_id;
        if (!state.enrolments.some((row) => row.student_id === student.id && row.groups.code === persona.groupCode)) {
          state.enrolments.push({
            student_id: student.id,
            status: "active",
            groups: { code: persona.groupCode }
          });
        }
        return [{
          persona: persona.persona,
          student_number: persona.studentNumber,
          display_name: persona.displayName,
          group_code: persona.groupCode,
          enrolment_status: "active",
          idempotent: Boolean(existing)
        }];
      }
      throw new Error(`unexpected rpc ${name}`);
    }
  };

  return { admin, rest, state };
}

test("missing env performs zero writes", async () => {
  const harness = createHarness();
  const logs = [];
  await assert.rejects(
    () => runProvision({
      env: { SUPABASE_URL: BASE_ENV.SUPABASE_URL },
      admin: harness.admin,
      rest: harness.rest,
      log: (...args) => logs.push(args.join(" "))
    }),
    /MISSING_REQUIRED_ENV/
  );
  assert.equal(harness.state.createCalls, 0);
  assert.deepEqual(harness.state.rpcCalls, []);
  const missing = collectMissingEnv({ SUPABASE_URL: BASE_ENV.SUPABASE_URL });
  assert.ok(missing.includes("SUPABASE_SERVICE_ROLE_KEY"));
  assert.ok(missing.includes("UNIT14_TEST_PASSWORD"));
});

test("new users are created then application-provisioned with returned Auth ids", async () => {
  const harness = createHarness();
  const logs = [];
  const outcome = await runProvision({
    env: BASE_ENV,
    admin: harness.admin,
    rest: harness.rest,
    log: (...args) => logs.push(args.join(" "))
  });
  assert.equal(outcome.ok, true);
  assert.equal(harness.state.createCalls, 4);
  const provisionCalls = harness.state.rpcCalls.filter((call) => call.name === "provision_synthetic_qa_learner");
  assert.equal(provisionCalls.length, 4);
  for (const call of provisionCalls) {
    assert.equal(typeof call.args.p_auth_user_id, "string");
    assert.ok(call.args.p_auth_user_id.startsWith("00000000-"));
  }
  assert.equal(harness.state.students.length, 4);
  assert.ok(harness.state.students.every((row) => row.contact_email == null));
  assert.deepEqual(harness.state.selectCalls, []);
  assert.ok(harness.state.rpcCalls.some((call) => call.name === "inspect_synthetic_qa_learners"));
  const text = logs.join("\n");
  for (const secret of secretValues()) {
    assert.equal(text.includes(secret), false);
  }
});

test("existing valid synthetic users are reused and passwords are not reset", async () => {
  const users = PERSONAS.map((persona, index) => ({
    id: `11111111-0000-4000-8000-00000000000${index + 1}`,
    email: BASE_ENV[persona.emailEnv[0]],
    email_confirmed_at: "2026-09-02T00:00:00Z",
    user_metadata: {
      synthetic: true,
      purpose: "formative-smoke-test",
      persona: persona.persona
    },
    app_metadata: { provider: "email" }
  }));
  const harness = createHarness({ users });
  const first = await runProvision({ env: BASE_ENV, admin: harness.admin, rest: harness.rest, log() {} });
  const second = await runProvision({ env: BASE_ENV, admin: harness.admin, rest: harness.rest, log() {} });
  assert.equal(first.ok, true);
  assert.equal(second.ok, true);
  assert.equal(harness.state.createCalls, 0);
  assert.equal(harness.state.passwordUpdates, 0);
  assert.equal(harness.state.students.length, 4);
  assert.equal(harness.state.enrolments.length, 4);
  assert.ok(second.results.every((row) => row.auth === "AUTH_REUSED"));
  assert.ok(second.results.every((row) => row.student === "REUSED"));
});

test("conflicting metadata stops without converting the account", async () => {
  const harness = createHarness({
    users: [{
      id: "22222222-0000-4000-8000-000000000001",
      email: BASE_ENV.UNIT3_TEST_EMAIL,
      email_confirmed_at: "2026-09-02T00:00:00Z",
      user_metadata: { synthetic: true, purpose: "formative-smoke-test", persona: "OTHER_PERSONA" },
      app_metadata: { provider: "email" }
    }]
  });
  const outcome = await runProvision({ env: BASE_ENV, admin: harness.admin, rest: harness.rest, log() {}, error() {} });
  assert.equal(outcome.ok, false);
  const unit3 = outcome.results.find((row) => row.persona === "UNIT3_TEST_LEARNER");
  assert.equal(unit3.code, "PERSONA_COLLISION");
  assert.equal(harness.state.createCalls, 3);
  assert.equal(harness.state.students.some((row) => row.student_number === "QA-UNIT3"), false);
});

test("duplicate emails and privileged accounts fail closed", () => {
  assert.throws(
    () => resolvePersonaSecrets({
      ...BASE_ENV,
      TLEVEL_TEST_EMAIL: BASE_ENV.UNIT3_TEST_EMAIL
    }),
    /DUPLICATE_QA_EMAIL/
  );
  assert.equal(isPrivilegedAppMetadata({ role: "staff" }), true);
  const staff = inspectAuthMetadata({
    email_confirmed_at: "2026-09-02T00:00:00Z",
    user_metadata: { synthetic: true, purpose: "formative-smoke-test", persona: "UNIT3_TEST_LEARNER" },
    app_metadata: { role: "admin" }
  }, "UNIT3_TEST_LEARNER");
  assert.equal(staff.code, "STAFF_ACCOUNT_FORBIDDEN");
  const ordinary = inspectAuthMetadata({
    email_confirmed_at: "2026-09-02T00:00:00Z",
    user_metadata: {},
    app_metadata: {}
  }, "UNIT3_TEST_LEARNER");
  assert.equal(ordinary.code, "NON_SYNTHETIC_ACCOUNT");
});

test("staff teacher rows and ordinary learners are not adopted", async () => {
  const staffHarness = createHarness({
    users: [{
      id: "44444444-0000-4000-8000-000000000001",
      email: BASE_ENV.UNIT3_TEST_EMAIL,
      email_confirmed_at: "2026-09-02T00:00:00Z",
      user_metadata: { synthetic: true, purpose: "formative-smoke-test", persona: "UNIT3_TEST_LEARNER" },
      app_metadata: {}
    }],
    teachers: [{ auth_user_id: "44444444-0000-4000-8000-000000000001" }]
  });
  const staffOutcome = await runProvision({
    env: BASE_ENV,
    admin: staffHarness.admin,
    rest: staffHarness.rest,
    log() {},
    error() {}
  });
  assert.equal(
    staffOutcome.results.find((row) => row.persona === "UNIT3_TEST_LEARNER").code,
    "STAFF_ACCOUNT_FORBIDDEN"
  );

  const learnerHarness = createHarness({
    users: [{
      id: "55555555-0000-4000-8000-000000000001",
      email: BASE_ENV.UNIT3_TEST_EMAIL,
      email_confirmed_at: "2026-09-02T00:00:00Z",
      user_metadata: { synthetic: true, purpose: "formative-smoke-test", persona: "UNIT3_TEST_LEARNER" },
      app_metadata: {}
    }],
    students: [{
      id: "real-student",
      student_number: "REAL-001",
      auth_user_id: "55555555-0000-4000-8000-000000000001",
      is_synthetic: false,
      contact_email: "kept-out-of-logs@example.test"
    }]
  });
  const learnerOutcome = await runProvision({
    env: BASE_ENV,
    admin: learnerHarness.admin,
    rest: learnerHarness.rest,
    log() {},
    error() {}
  });
  assert.equal(
    learnerOutcome.results.find((row) => row.persona === "UNIT3_TEST_LEARNER").code,
    "REAL_LEARNER_FORBIDDEN"
  );
});

test("linked Auth UUID cannot back a second QA persona", async () => {
  const harness = createHarness({
    users: [{
      id: "33333333-0000-4000-8000-000000000001",
      email: BASE_ENV.TLEVEL_TEST_EMAIL,
      email_confirmed_at: "2026-09-02T00:00:00Z",
      user_metadata: { synthetic: true, purpose: "formative-smoke-test", persona: "TLEVEL_TEST_LEARNER" },
      app_metadata: {}
    }],
    students: [{
      id: "student-wrong",
      student_number: "QA-CONFLICT",
      auth_user_id: "33333333-0000-4000-8000-000000000001",
      is_synthetic: true,
      contact_email: null
    }]
  });
  const outcome = await runProvision({ env: BASE_ENV, admin: harness.admin, rest: harness.rest, log() {}, error() {} });
  const tlevel = outcome.results.find((row) => row.persona === "TLEVEL_TEST_LEARNER");
  assert.equal(tlevel.code, "AUTH_ACCOUNT_ALREADY_LINKED");
});

test("dry-run inspects application state without direct learning REST and performs no writes", async () => {
  const harness = createHarness();
  const logs = [];
  const outcome = await runProvision({
    env: BASE_ENV,
    admin: harness.admin,
    rest: harness.rest,
    dryRun: true,
    log: (...args) => logs.push(args.join(" "))
  });
  const text = logs.join("\n");
  assert.equal(outcome.ok, true);
  assert.equal(harness.state.createCalls, 0);
  assert.equal(
    harness.state.rpcCalls.some((call) => call.name === "provision_synthetic_qa_learner"),
    false
  );
  assert.equal(
    harness.state.rpcCalls.some((call) => call.name === "ensure_synthetic_qa_groups"),
    false
  );
  assert.ok(harness.state.rpcCalls.some((call) => call.name === "inspect_synthetic_qa_learners"));
  assert.deepEqual(harness.state.selectCalls, []);
  assert.ok(text.includes("Auth: CREATE"));
  assert.ok(text.includes("Student: PROVISION"));
  assert.ok(text.includes("Enrolment: PROVISION"));
  assert.ok(text.includes("Assignment: READY"));
  assert.ok(text.includes("Status: PLANNED"));
  assert.equal(text.includes("REST_SELECT_FAILED"), false);
  for (const secret of secretValues()) {
    assert.equal(text.includes(secret), false);
  }
  assert.equal(maskEmail("qa+unit3@example.test").includes("qa+unit3@example.test"), false);
});

test("dry-run reports reuse when a synthetic learner already exists", async () => {
  const harness = createHarness({
    users: PERSONAS.map((persona, index) => ({
      id: `11111111-0000-4000-8000-00000000000${index + 1}`,
      email: BASE_ENV[persona.emailEnv[0]],
      email_confirmed_at: "2026-09-02T00:00:00Z",
      user_metadata: {
        synthetic: true,
        purpose: "formative-smoke-test",
        persona: persona.persona
      },
      app_metadata: { provider: "email" }
    })),
    students: PERSONAS.map((persona, index) => ({
      id: `student-${persona.studentNumber}`,
      student_number: persona.studentNumber,
      display_name: persona.displayName,
      auth_user_id: `11111111-0000-4000-8000-00000000000${index + 1}`,
      active: true,
      is_synthetic: true,
      synthetic_purpose: "formative-smoke-test",
      contact_email: null
    })),
    enrolments: PERSONAS.map((persona) => ({
      student_id: `student-${persona.studentNumber}`,
      status: "active",
      groups: { code: persona.groupCode }
    }))
  });
  const logs = [];
  const outcome = await runProvision({
    env: BASE_ENV,
    admin: harness.admin,
    rest: harness.rest,
    dryRun: true,
    log: (...args) => logs.push(args.join(" "))
  });
  const text = logs.join("\n");
  assert.equal(outcome.ok, true);
  assert.equal(harness.state.createCalls, 0);
  assert.ok(text.includes("Auth: REUSE"));
  assert.ok(text.includes("Student: READY"));
  assert.ok(text.includes("Enrolment: READY"));
  assert.ok(outcome.results.every((row) => row.auth === "AUTH_REUSED"));
});
