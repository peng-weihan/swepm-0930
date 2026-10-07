#!/usr/bin/env python3
"""Publish the two approved images on 10.161.41.9 using Docker's saved login."""
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.error
import urllib.parse
import urllib.request

HERE = Path(__file__).resolve().parent
NAMESPACE = "raymone23"
REPOSITORY = "swepm-0930"
REPO = NAMESPACE + "/" + REPOSITORY
HUB = "https://hub.docker.com"
REGISTRY = "https://registry-1.docker.io/v2/" + REPO
ACCEPT = ",".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])


def now():
    return datetime.now(timezone.utc).isoformat()


def request(url, method="GET", payload=None, bearer=None, accept="application/json"):
    headers = {"Accept": accept}
    if bearer:
        headers["Authorization"] = "Bearer " + bearer
    body = None
    if payload is not None:
        body = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=60) as response:
        raw = response.read()
        return response.status, dict(response.headers), raw


def json_request(*args, **kwargs):
    status, headers, raw = request(*args, **kwargs)
    return status, headers, json.loads(raw) if raw else None


def docker(*args, log=None):
    cmd = ["docker", *args]
    if log:
        with log.open("w") as output:
            result = subprocess.run(cmd, stdout=output, stderr=subprocess.STDOUT, timeout=3600)
        if result.returncode:
            raise RuntimeError("Docker command failed; inspect " + str(log))
        return log.read_text()
    return subprocess.check_output(cmd, text=True, timeout=60)


def save(data):
    temporary = HERE / "publication-result.json.new"
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(HERE / "publication-result.json")


def main():
    assert str(HERE).startswith("/data/"), "Run publication on the physical host under /data"
    os.umask(0o077)
    (HERE / "logs").mkdir(exist_ok=True)
    plan = json.loads((HERE / "dockerhub-plan.json").read_text())
    cfg = json.loads(Path("/root/.docker/config.json").read_text())
    username, secret = base64.b64decode(cfg["auths"]["https://index.docker.io/v1/"]["auth"]).decode().split(":", 1)
    assert username == NAMESPACE, "Unexpected Docker Hub login"
    _, _, auth = json_request(HUB + "/v2/auth/token", method="POST", payload={"identifier": username, "secret": secret})
    bearer = auth["access_token"]
    repo_url = HUB + "/v2/namespaces/" + NAMESPACE + "/repositories/" + REPOSITORY
    created = False
    try:
        _, _, repository = json_request(repo_url, bearer=bearer)
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        metadata = {
            "namespace": NAMESPACE, "name": REPOSITORY, "registry": "docker.io", "is_private": False,
            "description": "Repaired environment images for the SWEPM 0930 benchmark",
            "full_description": "Two environment repairs for the SWEPM 0930 benchmark.\n\n"
            "- aimee-1c60c9c-env-20261003-r2: PostgreSQL and Zstandard development dependencies.\n"
            "- devlake-8877-env-20261003-r2: CMake, libgit2 1.3.0, mockery, generated Go mocks, "
            "database development dependencies and the Azure DevOps Python plugin environment.\n\n"
            "Both derive from the corresponding key4127/refactor-dockerhub base images. "
            "Published images are identical to the locally validated repaired images. "
            "The evaluated candidate patch and verifier are supplied separately by the benchmark.\n",
        }
        status, _, repository = json_request(HUB + "/v2/namespaces/" + NAMESPACE + "/repositories", method="POST", payload=metadata, bearer=bearer)
        assert status == 201
        created = True
    assert repository.get("is_private") is False, "Public benchmark repository expected"
    result = {"started_at": now(), "source_host": "10.161.41.9", "repository": REPO,
              "repository_url": "https://hub.docker.com/r/" + REPO, "repository_created": created,
              "is_private": repository["is_private"], "status": "publishing", "images": []}
    save(result)
    print("Repository ready: " + REPO, flush=True)
    for item in plan["images"]:
        src = item["source_image"]
        dest = "docker.io/" + REPO + ":" + item["proposed_tag"]
        source = json.loads(docker("image", "inspect", src))[0]
        assert source["Id"] == item["local_image_id"], "Source image has changed"
        tag_log = HERE / "logs" / (item["proposed_tag"] + ".push.log")
        print(now() + " Pushing " + dest, flush=True)
        docker("image", "tag", src, dest)
        docker("push", dest, log=tag_log)
        print(now() + " Push complete; verifying public manifest and pull", flush=True)
        scope = urllib.parse.urlencode({"service": "registry.docker.io", "scope": "repository:" + REPO + ":pull"})
        _, _, anonymous_auth = json_request("https://auth.docker.io/token?" + scope)
        public_bearer = anonymous_auth.get("token") or anonymous_auth["access_token"]
        _, headers, raw = request(REGISTRY + "/manifests/" + item["proposed_tag"], bearer=public_bearer, accept=ACCEPT)
        digest = "sha256:" + hashlib.sha256(raw).hexdigest()
        declared = next((v for k, v in headers.items() if k.lower() == "docker-content-digest"), None)
        assert digest == declared
        manifest = json.loads(raw)
        platform_digest = digest
        if "manifests" in manifest:
            descriptor = next(x for x in manifest["manifests"] if x.get("platform", {}).get("os") == "linux" and x.get("platform", {}).get("architecture") == "amd64")
            platform_digest = descriptor["digest"]
            _, _, platform_raw = request(REGISTRY + "/manifests/" + platform_digest, bearer=public_bearer, accept=ACCEPT)
            assert "sha256:" + hashlib.sha256(platform_raw).hexdigest() == platform_digest
            manifest = json.loads(platform_raw)
        _, _, config_raw = request(REGISTRY + "/blobs/" + manifest["config"]["digest"], bearer=public_bearer)
        assert "sha256:" + hashlib.sha256(config_raw).hexdigest() == manifest["config"]["digest"]
        config = json.loads(config_raw)
        assert config["rootfs"]["diff_ids"] == source["RootFS"]["Layers"]
        for layer in manifest["layers"]:
            status, _, _ = request(REGISTRY + "/blobs/" + layer["digest"], method="HEAD", bearer=public_bearer)
            assert status == 200
        pull_log = HERE / "logs" / (item["proposed_tag"] + ".pull.log")
        pinned = "docker.io/" + REPO + "@" + digest
        docker("pull", pinned, log=pull_log)
        pulled = json.loads(docker("image", "inspect", pinned))[0]
        assert pulled["Id"] == source["Id"]
        row = {"instance_id": item["instance_id"], "source_image": src, "source_image_id": source["Id"],
               "destination_image": dest, "digest_reference": pinned, "manifest_digest": digest,
               "platform_manifest_digest": platform_digest, "config_digest": manifest["config"]["digest"],
               "compressed_layer_bytes": sum(x["size"] for x in manifest["layers"]),
               "layer_count": len(manifest["layers"]), "anonymous_manifest_and_layers_verified": True,
               "rootfs_identical": True, "docker_pull_succeeded": True, "pulled_image_id": pulled["Id"],
               "verified_at": now(), "push_log": str(tag_log), "pull_log": str(pull_log)}
        result["images"].append(row)
        save(result)
        print(json.dumps(row), flush=True)
    result.update(status="published_and_verified", finished_at=now())
    save(result)
    print("Published and verified both images", flush=True)


if __name__ == "__main__":
    main()
