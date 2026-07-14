# Intentionally empty. Its presence here (at the app/ level, a sibling of
# tests/) is what makes `from main import app` work inside
# tests/test_main.py: pytest's default "prepend" import mode adds the
# directory containing the topmost conftest.py to sys.path automatically.
# Without this file, pytest only adds tests/ itself to sys.path — not app/ —
# so main.py (which lives in app/, not app/tests/) can't be found, regardless
# of which directory you happen to run `pytest` from.