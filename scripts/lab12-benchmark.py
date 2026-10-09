#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import os
import platform
import shlex
import signal
import socket
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
TOOL_ROOT = ROOT / ".goenv" / "lab12"
EVIDENCE = TOOL_ROOT / "evidence"
SPIN = TOOL_ROOT / "bin" / "spin"
WASMTIME = TOOL_ROOT / "bin" / "wasmtime"
HYPERFINE = TOOL_ROOT / "bin" / "hyperfine"
CURL = Path("/usr/bin/curl")
DOCKER = Path("/usr/bin/docker")
SPIN_HOST = "127.0.0.1"
SPIN_PORT = 3012
SPIN_URL = f"http://{SPIN_HOST}:{SPIN_PORT}/time"
DOCKER_URL = "http://127.0.0.1:18082/health"
CONTAINER_NAME = "quicknotes-lab12-benchmark"


def command(args: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=True, text=True, **kwargs)


def wait_http(url: str, process: subprocess.Popen[str] | None = None) -> str:
    deadline = time.monotonic() + 20
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        if process is not None and process.poll() is not None:
            raise RuntimeError(f"process exited early with status {process.returncode}")
        try:
            with urllib.request.urlopen(url, timeout=0.25) as response:
                body = response.read().decode("utf-8")
                if response.status == 200:
                    if process is not None:
                        time.sleep(0.05)
                        if process.poll() is not None:
                            raise RuntimeError(
                                f"process exited early with status {process.returncode}"
                            )
                    return body
        except (OSError, urllib.error.URLError) as error:
            last_error = error
        time.sleep(0.005)
    raise RuntimeError(f"{url} did not become ready: {last_error}")


def ensure_port_available(host: str, port: int) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            probe.bind((host, port))
        except OSError as error:
            raise RuntimeError(
                f"benchmark port {host}:{port} is already in use"
            ) from error


def start_spin() -> tuple[subprocess.Popen[str], object]:
    ensure_port_available(SPIN_HOST, SPIN_PORT)
    log_handle = (EVIDENCE / "spin.log").open("a", encoding="utf-8")
    process = subprocess.Popen(
        [str(SPIN), "up", "--listen", f"{SPIN_HOST}:{SPIN_PORT}"],
        cwd=ROOT / "wasm",
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    return process, log_handle


def stop_spin(process: subprocess.Popen[str], log_handle: object) -> None:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
    log_handle.close()  # type: ignore[attr-defined]


def choose_docker_image() -> str:
    requested = os.environ.get("LAB12_DOCKER_IMAGE")
    candidates = [
        requested,
        "quicknotes:lab6",
        "qn-lab6:run1",
        "quicknotes:lab8",
    ]
    for image in candidates:
        if not image:
            continue
        result = subprocess.run(
            [str(DOCKER), "image", "inspect", image],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            return image
    raise RuntimeError(
        "No Lab 6 image found. Set LAB12_DOCKER_IMAGE to its local image tag."
    )


def stop_docker() -> None:
    subprocess.run(
        [str(DOCKER), "rm", "-f", CONTAINER_NAME],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def start_docker(image: str) -> None:
    stop_docker()
    command(
        [
            str(DOCKER),
            "run",
            "--rm",
            "--detach",
            "--name",
            CONTAINER_NAME,
            "--publish",
            "127.0.0.1:18082:8080",
            "--tmpfs",
            "/data:rw,noexec,nosuid,nodev,size=16m,uid=65532,gid=65532,mode=0750",
            "--env",
            "DATA_PATH=/data/notes.json",
            image,
        ],
        stdout=subprocess.DEVNULL,
    )


def percentile(values: list[float], quantile: float) -> float:
    ordered = sorted(values)
    index = max(0, math.ceil(quantile * len(ordered)) - 1)
    return ordered[index]


def summarize_seconds(values: list[float]) -> dict[str, object]:
    return {
        "samples_seconds": values,
        "p50_ms": round(statistics.median(values) * 1000, 3),
        "p95_ms": round(percentile(values, 0.95) * 1000, 3),
    }


def hyperfine(url: str, output: Path) -> dict[str, object]:
    if output.exists():
        output.unlink()
    measured = f"{shlex.quote(str(CURL))} --fail --silent --output /dev/null {shlex.quote(url)}"
    command(
        [
            str(HYPERFINE),
            "--warmup",
            "5",
            "--runs",
            "50",
            "--export-json",
            str(output),
            measured,
        ]
    )
    data = json.loads(output.read_text(encoding="utf-8"))
    times = [float(value) for value in data["results"][0]["times"]]
    return summarize_seconds(times)


def cold_spin(samples: int) -> list[float]:
    values: list[float] = []
    for index in range(samples):
        started = time.perf_counter()
        process, log_handle = start_spin()
        try:
            wait_http(SPIN_URL, process)
            values.append(time.perf_counter() - started)
            print(f"spin cold {index + 1}/{samples}: {values[-1] * 1000:.3f} ms")
        finally:
            stop_spin(process, log_handle)
    return values


def cold_docker(image: str, samples: int) -> list[float]:
    values: list[float] = []
    for index in range(samples):
        started = time.perf_counter()
        start_docker(image)
        try:
            wait_http(DOCKER_URL)
            values.append(time.perf_counter() - started)
            print(f"docker cold {index + 1}/{samples}: {values[-1] * 1000:.3f} ms")
        finally:
            stop_docker()
    return values


def cold_wasmtime(samples: int) -> tuple[list[float], str]:
    values: list[float] = []
    output = ""
    for index in range(samples):
        started = time.perf_counter()
        result = command(
            [
                str(WASMTIME),
                "run",
                "--env",
                "REQUEST_METHOD=GET",
                "--env",
                "PATH_INFO=/time",
                str(ROOT / "wasm-cli" / "main.wasm"),
            ],
            capture_output=True,
        )
        values.append(time.perf_counter() - started)
        output = result.stdout
        if '"timezone":"Europe/Moscow (UTC+3)"' not in output:
            raise RuntimeError("standalone WASI response did not contain Moscow JSON")
        print(f"wasmtime cold {index + 1}/{samples}: {values[-1] * 1000:.3f} ms")
    return values, output


def main() -> int:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    spin_log = EVIDENCE / "spin.log"
    if spin_log.exists():
        spin_log.unlink()
    for executable in (SPIN, WASMTIME, HYPERFINE, CURL, DOCKER):
        if not executable.exists():
            raise RuntimeError(f"missing required executable: {executable}")
    if not (ROOT / "wasm" / "main.wasm").exists():
        raise RuntimeError("run scripts/lab12-build.sh first")
    if not (ROOT / "wasm-cli" / "main.wasm").exists():
        raise RuntimeError("run scripts/lab12-build.sh first")

    image = choose_docker_image()
    print(f"Docker baseline: {image}")
    spin_cold = cold_spin(5)
    docker_cold = cold_docker(image, 5)

    spin_process, spin_log = start_spin()
    try:
        spin_response = wait_http(SPIN_URL, spin_process)
        start_docker(image)
        try:
            docker_response = wait_http(DOCKER_URL)
            spin_warm = hyperfine(SPIN_URL, EVIDENCE / "spin-warm.json")
            docker_warm = hyperfine(DOCKER_URL, EVIDENCE / "docker-warm.json")
        finally:
            stop_docker()
    finally:
        stop_spin(spin_process, spin_log)

    wasmtime_values, wasmtime_response = cold_wasmtime(20)
    inspect = command(
        [str(DOCKER), "image", "inspect", image], capture_output=True
    )
    docker_metadata = json.loads(inspect.stdout)[0]

    cpu_model = "unknown"
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
        for line in cpuinfo.read_text(encoding="utf-8").splitlines():
            if line.startswith("model name"):
                cpu_model = line.split(":", 1)[1].strip()
                break

    metrics = {
        "test_rig": {
            "platform": platform.platform(),
            "cpu": cpu_model,
            "python": platform.python_version(),
        },
        "tool_versions": {
            "spin": command([str(SPIN), "--version"], capture_output=True).stdout.strip(),
            "wasmtime": command([str(WASMTIME), "--version"], capture_output=True).stdout.strip(),
            "hyperfine": command([str(HYPERFINE), "--version"], capture_output=True).stdout.strip(),
        },
        "artifacts": {
            "spin_wasm_bytes": (ROOT / "wasm" / "main.wasm").stat().st_size,
            "wasi_cli_bytes": (ROOT / "wasm-cli" / "main.wasm").stat().st_size,
            "docker_image": image,
            "docker_image_id": docker_metadata["Id"],
            "docker_image_bytes": docker_metadata["Size"],
        },
        "cold_start": {
            "spin": summarize_seconds(spin_cold),
            "docker": summarize_seconds(docker_cold),
            "wasmtime_cli": summarize_seconds(wasmtime_values),
        },
        "warm_latency": {"spin": spin_warm, "docker": docker_warm},
        "responses": {
            "spin": json.loads(spin_response),
            "docker": json.loads(docker_response),
            "wasmtime_cli": wasmtime_response,
        },
    }
    output = EVIDENCE / "metrics.json"
    output.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")

    print("\n| Dimension | Lab 6 Docker | Lab 12 WASM/Spin |")
    print("|---|---:|---:|")
    print(
        f"| Artifact size | {docker_metadata['Size']} bytes | "
        f"{metrics['artifacts']['spin_wasm_bytes']} bytes |"
    )
    print(
        f"| Cold start p50 | {metrics['cold_start']['docker']['p50_ms']} ms | "
        f"{metrics['cold_start']['spin']['p50_ms']} ms |"
    )
    print(
        f"| Warm latency p50 | {docker_warm['p50_ms']} ms | "
        f"{spin_warm['p50_ms']} ms |"
    )
    print(
        f"| Warm latency p95 | {docker_warm['p95_ms']} ms | "
        f"{spin_warm['p95_ms']} ms |"
    )
    print(f"\nStandalone Wasmtime p50: {metrics['cold_start']['wasmtime_cli']['p50_ms']} ms")
    print(f"Evidence: {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"lab12 benchmark failed: {error}", file=sys.stderr)
        stop_docker()
        raise
