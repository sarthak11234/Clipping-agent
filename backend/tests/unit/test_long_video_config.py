from src.config import Config


def test_long_video_timeouts_can_be_raised(monkeypatch):
    monkeypatch.setenv("VIDEO_JOB_TIMEOUT_SECONDS", "25200")
    monkeypatch.setenv("PROCESSING_TASK_TIMEOUT_SECONDS", "28800")
    monkeypatch.setenv("TRANSCRIPT_ANALYSIS_TOTAL_TIMEOUT_SECONDS", "7200")

    config = Config()

    assert config.video_job_timeout_seconds == 25200
    assert config.processing_task_timeout_seconds == 28800
    assert config.transcript_analysis_total_timeout_seconds == 7200


def test_stale_processing_sweep_outlasts_the_worker_job(monkeypatch):
    # A long video must not be marked "stalled" while its ARQ job is still
    # running, even if the two environment variables are set inconsistently.
    monkeypatch.setenv("VIDEO_JOB_TIMEOUT_SECONDS", "25200")
    monkeypatch.setenv("PROCESSING_TASK_TIMEOUT_SECONDS", "100")

    config = Config()

    assert config.processing_task_timeout_seconds == 25200 + 3600
