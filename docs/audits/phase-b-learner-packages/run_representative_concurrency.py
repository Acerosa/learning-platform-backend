#!/usr/bin/env python3
"""Local Phase B concurrency bench via public PostgREST curriculum RPC.

Builds representative nested activity packages (under the 4 MiB staff package
limit), stores Phase B learner packages, then issues cold concurrent anon RPC
calls with the existing 3s anon statement_timeout.
"""

from __future__ import annotations

import json
import statistics
import subprocess
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

DB = "supabase_db_learning-platform-backend"
API = "http://127.0.0.1:56321"
ANON = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9."
    "CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
)
HUB = "unit-3-cyber-security"
COURSE = "ocr-level-3-it"
OUT = Path(__file__).with_name("representative_concurrency.txt")


def psql(sql: str) -> str:
    return subprocess.check_output(
        ["docker", "exec", "-i", DB, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c", sql],
        text=True,
    ).strip()


def ensure_synthetic(activities: int, version: str) -> dict:
    """Insert/replace a superseded synthetic publication with nested complexity.

    408 uses tiled seed activities (T Level–scale realism under 4 MiB staff).
    1000/2000 use compact nested templates so staff packages stay under 4 MiB
    while retaining paragraph / teacher-note / single-choice structure.
    """
    # Rich seed tiling only fits under the 4 MiB staff limit near ~408 activities.
    rich = activities <= 408
    psql(
        f"""
        do $do$
        declare
          v_base jsonb;
          v_acts jsonb;
          v_pkg jsonb;
          v_learn jsonb;
          v_hash text;
          v_auth uuid;
          v_staff text;
          v_target int := {activities};
          v_base_n int;
          v_version text := '{version}';
          v_rich boolean := {str(rich).lower()};
        begin
          select package into v_base
          from platform.curriculum_publications
          where hub_code = '{HUB}' and status = 'published'
          order by published_at desc limit 1;

          v_base_n := jsonb_array_length(coalesce(v_base->'activities', '[]'::jsonb));
          if v_base_n < 1 then
            raise exception 'no base activities';
          end if;

          if v_rich then
            select coalesce(jsonb_agg(value), '[]'::jsonb) into v_acts
            from (
              select value from (
                select value, row_number() over () as rn
                from generate_series(1, ceil(v_target::numeric / greatest(v_base_n, 1))::int) as gs(i)
                cross join lateral jsonb_array_elements(coalesce(v_base->'activities', '[]'::jsonb)) e(value)
              ) numbered
              where rn <= v_target
            ) lim;
          else
            select coalesce(jsonb_agg(act order by ord), '[]'::jsonb) into v_acts
            from (
              select
                gs.i as ord,
                jsonb_build_object(
                  'id', 'synth-act-' || gs.i::text,
                  'version', '1.0.0',
                  'title', 'Synthetic activity ' || gs.i::text,
                  'blocks', jsonb_build_array(
                    jsonb_build_object(
                      'type', 'paragraph',
                      'content', jsonb_build_object(
                        'text',
                        'Representative nested paragraph content for concurrency fixture '
                        || gs.i::text
                        || ' with enough body text to approximate learner payload density.'
                      )
                    ),
                    jsonb_build_object(
                      'type', 'teacher-note',
                      'content', jsonb_build_object(
                        'text', 'STAFF ONLY marking guidance ' || gs.i::text
                      )
                    ),
                    jsonb_build_object(
                      'type', 'single-choice',
                      'content', jsonb_build_object(
                        'prompt', 'Which option is correct for item ' || gs.i::text || '?',
                        'correctOptionId', 'A',
                        'options', jsonb_build_array(
                          jsonb_build_object('id', 'A', 'label', 'Correct'),
                          jsonb_build_object('id', 'B', 'label', 'Distractor B'),
                          jsonb_build_object('id', 'C', 'label', 'Distractor C')
                        )
                      )
                    )
                  )
                ) as act
              from generate_series(1, v_target) as gs(i)
            ) built;
          end if;

          v_pkg := jsonb_set(v_base, '{{activities}}', v_acts, true);
          if octet_length(v_pkg::text) > 4194304 then
            raise exception 'staff package exceeds 4MiB for % activities (%)', v_target, octet_length(v_pkg::text);
          end if;

          v_learn := platform.learner_curriculum_package(v_pkg, v_version, '0.1.0');
          v_hash := encode(extensions.digest(v_pkg::text, 'sha256'), 'hex');

          select published_by_auth_user_id, published_by_staff_reference
          into v_auth, v_staff
          from platform.curriculum_publications
          where hub_code = '{HUB}'
          order by published_at desc limit 1;

          -- Local bench only: disable immutability trigger to refresh fixtures.
          alter table platform.curriculum_publications
            disable trigger protect_curriculum_publication;

          delete from platform.curriculum_publications
          where hub_code = '{HUB}' and course_key = '{COURSE}' and package_version = v_version;

          insert into platform.curriculum_publications (
            hub_code, course_key, package_version, schema_version, source_package_version,
            status, package, learner_package, learner_package_sanitisation_version,
            content_hash, author, reviewer, publication_notes,
            published_by_auth_user_id, published_by_staff_reference
          ) values (
            '{HUB}', '{COURSE}', v_version, '0.1.0', '0.1.0',
            'superseded', v_pkg, v_learn, platform.learner_package_sanitisation_version(),
            v_hash, 'phase-b-bench', '', 'representative concurrency fixture',
            v_auth, v_staff
          );

          alter table platform.curriculum_publications
            enable trigger protect_curriculum_publication;
        exception
          when others then
            alter table platform.curriculum_publications
              enable trigger protect_curriculum_publication;
            raise;
        end;
        $do$;
        """
    )
    meta = psql(
        f"""
        select jsonb_build_object(
          'activities', jsonb_array_length(coalesce(package->'activities','[]'::jsonb)),
          'staff_bytes', pg_column_size(package),
          'learner_bytes', pg_column_size(learner_package),
          'staff_text_bytes', octet_length(package::text),
          'learner_text_bytes', octet_length(learner_package::text),
          'learner_md5', md5(learner_package::text),
          'phase_a_md5', md5(platform.learner_curriculum_package(package, package_version, source_package_version)::text),
          'equal', learner_package = platform.learner_curriculum_package(package, package_version, source_package_version)
        )::text
        from platform.curriculum_publications
        where package_version = '{version}';
        """
    )
    return json.loads(meta)


def rpc_once(version: str) -> dict:
    body = json.dumps(
        {"p_hub_code": HUB, "p_course_key": COURSE, "p_package_version": version}
    ).encode()
    req = urllib.request.Request(
        f"{API}/rest/v1/rpc/published_curriculum_package",
        data=body,
        headers={
            "apikey": ANON,
            "Authorization": f"Bearer {ANON}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Content-Profile": "api",
            "Accept-Profile": "api",
            "Cache-Control": "no-store",
        },
        method="POST",
    )
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            raw = resp.read()
            ms = (time.perf_counter() - t0) * 1000
            data = json.loads(raw)
            if isinstance(data, list):
                data = data[0] if data else {}
            pkg = data.get("package") if isinstance(data, dict) else None
            acts = len((pkg or {}).get("activities") or []) if isinstance(pkg, dict) else None
            return {
                "ok": True,
                "http": resp.status,
                "ms": ms,
                "bytes": len(raw),
                "activities": acts,
                "err": None,
                "timeout": False,
            }
    except Exception as e:
        ms = (time.perf_counter() - t0) * 1000
        err = b""
        if hasattr(e, "read"):
            try:
                err = e.read()
            except Exception:
                pass
        text = err.decode("utf-8", "replace") if err else str(e)
        return {
            "ok": False,
            "http": getattr(e, "code", None),
            "ms": ms,
            "bytes": 0,
            "activities": None,
            "err": text[:400],
            "timeout": "57014" in text or "statement timeout" in text.lower(),
        }


def db_exec_ms(version: str, samples: int = 5) -> dict:
    rows = []
    for _ in range(samples):
        ms = int(
            psql(
                f"""
                select (extract(epoch from (clock_timestamp()-t0))*1000)::int
                from (select clock_timestamp() as t0) s,
                lateral (
                  select 1
                  from api.published_curriculum_package('{HUB}', '{COURSE}', '{version}')
                ) x;
                """
            )
        )
        rows.append(ms)
    return {
        "min": min(rows),
        "median": int(statistics.median(rows)),
        "p95": sorted(rows)[max(0, int(0.95 * (len(rows) - 1)))],
        "max": max(rows),
    }


def pct(vals, p):
    if not vals:
        return None
    s = sorted(vals)
    idx = min(len(s) - 1, max(0, int(round((p / 100) * (len(s) - 1)))))
    return s[idx]


def bench(version: str, activities: int, workers: int, trials: int = 3) -> dict:
    all_ms = []
    errors = 0
    timeouts = 0
    bytes_ = None
    integrity_ok = True
    for _ in range(trials):
        with ThreadPoolExecutor(max_workers=workers) as ex:
            futs = [ex.submit(rpc_once, version) for _ in range(workers)]
            for f in as_completed(futs):
                r = f.result()
                all_ms.append(r["ms"])
                if not r["ok"]:
                    errors += 1
                    if r["timeout"]:
                        timeouts += 1
                else:
                    bytes_ = r["bytes"]
                    if r["activities"] != activities:
                        integrity_ok = False
    return {
        "workers": workers,
        "trials": trials,
        "calls": len(all_ms),
        "min": min(all_ms) if all_ms else None,
        "median": statistics.median(all_ms) if all_ms else None,
        "p95": pct(all_ms, 95),
        "max": max(all_ms) if all_ms else None,
        "errors": errors,
        "timeouts": timeouts,
        "bytes": bytes_,
        "integrity_ok": integrity_ok,
    }


def main():
    lines = []
    configs = [
        (408, "9.0.408"),
        (1000, "9.0.1000"),
        (2000, "9.0.2000"),
    ]
    for n, ver in configs:
        meta = ensure_synthetic(n, ver)
        lines.append(f"=== PACKAGE {n} version={ver} meta={json.dumps(meta)} ===")
        db = db_exec_ms(ver)
        lines.append(f"db_exec_ms={json.dumps(db)}")
        for w in (1, 5, 10, 20, 30, 50):
            # Warm connection pool lightly then cold-ish concurrent burst
            rpc_once(ver)
            time.sleep(0.2)
            result = bench(ver, n, w, trials=3 if w <= 10 else 2)
            line = (
                f"n_act={n} workers={w} min={result['min']:.0f} med={result['median']:.0f} "
                f"p95={result['p95']:.0f} max={result['max']:.0f} bytes={result['bytes']} "
                f"errors={result['errors']} timeouts={result['timeouts']} "
                f"integrity={result['integrity_ok']} calls={result['calls']}"
            )
            print(line)
            lines.append(line)
    OUT.write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
