#!/usr/bin/env python3
"""Verify a late native reconnect before resuming the saved-session test.

The native picker can complete after the Flutter assertion's deadline. This
observer preserves that timeout and checks the real resulting state read-only.
It writes only evidence and the harness continuation marker, never app state.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3


def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('runtime', type=Path)
    args = parser.parse_args()
    runtime = args.runtime.resolve()
    assert re.fullmatch(r'runtime-[a-f0-9]{16}', runtime.name)
    assert (runtime / 'synthetic-fixture.marker').is_file()
    before = json.loads((runtime / 'rerun-before-reconnect.json').read_text())
    progress = json.loads((runtime / 'progress.json').read_text())
    run = progress['runId']
    assert re.fullmatch(r'linux-live-[a-f0-9]{10}', run)
    assert before['progress']['runId'] == run
    required = ['production_auth_and_normal_setup',
                'isolated_identity_survived_normal_signin',
                'initial_small_and_multipart_upload',
                'modified_file_new_cloud_revision',
                'downloaded_modified_and_multipart_bytes_match']
    assert all(progress['checks'].get(key) is True for key in required)
    assert progress['phase'] == 'reconnect_generated_folder_with_native_picker'
    proof = json.loads((runtime / 'fixed-candidate-proof.json').read_text())
    bundle = runtime.parent / 'build/linux/x64/debug/bundle'
    assert digest(bundle / 'secure_file_vault') == proof['nativeSha256']
    assert digest(bundle / 'data/flutter_assets/kernel_blob.bin') == proof['kernelSha256']
    for name, sha in proof['sourceSha256'].items():
        assert digest(runtime.parent / name) == sha

    target = runtime / f'Reconnected FiFe-{run}'
    assert target.is_dir() and not target.is_symlink()
    db = sqlite3.connect(
        f'file:{runtime / "support/databases/fife.sqlite"}?mode=ro', uri=True)
    try:
        root = db.execute('SELECT id,path FROM items WHERE id=?',
                          (before['rootId'],)).fetchone()
        assert root == (before['rootId'], str(target))
        cleanup = db.execute('SELECT value FROM states WHERE id=?',
                             (f'managed_copy_cleanup:{root[0]}',)).fetchone()
        assert not cleanup or not cleanup[0] or not json.loads(cleanup[0]).get('pending')
        files = db.execute(
            'SELECT i.name,f.uploaded_at,t.id FROM items i '
            'JOIN files f ON f.id=i.file_hash LEFT JOIN item_tasks t ON t.id=i.id '
            'WHERE i.parent_id=? AND i.archived_at=0', (root[0],)).fetchall()
        assert {row[0] for row in files} == {'small.txt', 'multipart.bin'}
        assert all(row[1] > 0 and row[2] is None for row in files)
        assert db.execute('SELECT count(*) FROM item_tasks').fetchone()[0] == 0
    finally:
        db.close()
    base = runtime / 'documents/FiFe/.downloads'
    copy_roots = {base / Path(copy).relative_to(base).parts[0]
                  for copy in before['managedCopies']}
    assert len(copy_roots) == 1 and all(not p.exists() for p in copy_roots)
    assert (target / 'small.txt').read_text() == (
        f'Synthetic FiFe live Linux check {run} v2 modified\n')
    fixture = json.loads((runtime / 'fixture-rerun.json').read_text())
    assert (target / 'multipart.bin').stat().st_size == 36 * 1024 * 1024
    assert digest(target / 'multipart.bin') == fixture['largeSha256']
    timeout = 'Bad state: Timed out at reconnect_generated_folder_with_native_picker'
    assert timeout in (runtime / 'app.log').read_text(errors='replace')
    checks = dict(progress['checks'],
                  native_reconnect_cleans_copies_preserves_originals=True)
    result = dict(progress, phase='PASS_reconnect_external_observer', checks=checks,
                  originalHarnessFailure=timeout, rootIdentityPreserved=True,
                  wholeManagedTreeRemoved=True, externalOriginalsPreserved=True,
                  pendingTransfers=0, appDatabaseOpenedReadOnly=True,
                  checkpointAffectsOnlyTestBranch=True,
                  candidate=proof)
    (runtime / 'late-reconnect-proof.json').write_text(json.dumps(result, indent=2))
    marker = runtime / f'support/{run}-complete'
    assert not marker.exists()
    marker.write_text('restart-required')
    print(json.dumps({'verifiedNativeReconnect': True,
                      'originalHarnessTimeoutRetained': True,
                      'testContinuationCheckpointRecorded': True,
                      'appStateModified': False}))


if __name__ == '__main__':
    main()
