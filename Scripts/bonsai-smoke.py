import hashlib,json,pathlib
from huggingface_hub import snapshot_download
repo="litert-community/Bonsai-Image-ternary-4B"
revision="317d577f5f962eb2d5a3980bca2ce047a8338212"
root=pathlib.Path("/tmp/bonsai-model")
names={"textenc_int4.tflite","dit_256_int4b32.tflite","vae_dec_256_fp32.tflite"}
snapshot_download(repo_id=repo,revision=revision,local_dir=root,allow_patterns=[*names,"generate.py","pipeline_meta.json","tokenizer/*"])
manifest=json.loads(pathlib.Path("BonsaiResources/bonsai_manifest.json").read_text())
for row in manifest["files"]:
    if row["name"] not in names:
        continue
    path=root/row["name"]
    assert path.stat().st_size==row["bytes"]
    with path.open("rb") as f:
        assert f.read(8)[4:8]==b"TFL3"
        f.seek(0)
        digest=hashlib.file_digest(f,"sha256").hexdigest()
    assert digest==row["sha256"],path
    print("PASS: pinned size, format, SHA-256:",path.name,flush=True)
