import os
import pytest


def pytest_addoption(parser):
    parser.addoption(
        "--run-aws",
        action="store_true",
        default=False,
        help="Run AWS integration tests (or set RUN_AWS_INTEGRATION=1)"
    )


def pytest_collection_modifyitems(config, items):
    """
    By default skip tests marked with `@pytest.mark.integration` unless either:
    - the `--run-aws` flag is passed to pytest, or
    - the environment variable `RUN_AWS_INTEGRATION` is set to `1`.
    This keeps unit test runs fast and safe by default.
    """
    run_aws = config.getoption("--run-aws") or os.getenv("RUN_AWS_INTEGRATION") == "1"
    if not run_aws:
        skip_marker = pytest.mark.skip(reason=(
            "AWS integration tests disabled. Set RUN_AWS_INTEGRATION=1 or use --run-aws to enable."
        ))
        for item in items:
            if "integration" in item.keywords:
                item.add_marker(skip_marker)
