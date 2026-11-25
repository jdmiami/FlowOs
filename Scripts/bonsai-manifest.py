import json, pathlib, urllib.request, hashlib
repo = "litert-community/Bonsai-Image-ternary-4B"
revision = "317d577f5f962eb2d5a3980bca2ce047a8338212"
names = ["textenc_int4.tflite", "dit_256_int4b32.tflite", "dit_int4b32.tflite", "vae_dec_256_fp32.tflite", "vae_dec_fp32.tflite"]
out = pathlib.Path("BonsaiResources")
out.mkdir(exist_ok=True)
url = f"https://huggingface.co/api/models/{repo}/revision/{revision}?blobs=true"
with urllib.request.urlopen(url, timeout=90) as response:
    info = json.load(response)
assert info["sha"] == revision
files = {x["rfilename"]: x for x in info["siblings"]}
manifest = []
for name in names:
    lfs = files[name]["lfs"]
    size = int(lfs["size"])
    sha = lfs["sha256"]
    assert size > 0 and len(sha) == 64 and all(c in "0123456789abcdef" for c in sha)
    manifest.append(dict(name=name, bytes=size, sha256=sha))
(out / "bonsai_manifest.json").write_text(json.dumps(dict(revision=revision, files=manifest), indent=2))
for name in ["tokenizer/vocab.json", "tokenizer/merges.txt", "pipeline_meta.json"]:
    with urllib.request.urlopen(f"https://huggingface.co/{repo}/resolve/{revision}/{name}", timeout=90) as response:
        data = response.read(30_000_001)
    assert 0 < len(data) <= 30_000_000
    # Verify the Git object or LFS digest advertised at the pinned revision.
    row = files[name]
    if "lfs" in row and row["lfs"]:
        assert hashlib.sha256(data).hexdigest() == row["lfs"]["sha256"]
    else:
        assert hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest() == row["blobId"]
    (out / pathlib.Path(name).name).write_bytes(data)
print("Pinned model manifest and tokenizer resources prepared.")
