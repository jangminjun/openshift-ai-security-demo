"""Toy tool-using agent: asks an OpenAI-compatible model what to do with a document
and executes the single shell command the model returns.
Usage: python3 agent.py <document>   (env: OPENAI_BASE_URL, optional MODEL)
Demo only. It executes model output on purpose to show the sandbox boundary."""
import json, os, re, subprocess, sys, urllib.request

base = os.environ["OPENAI_BASE_URL"].rstrip("/")

def call(path, body=None):
    req = urllib.request.Request(base + path, data=json.dumps(body).encode() if body else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)

model = os.environ.get("MODEL") or call("/models")["data"][0]["id"]
doc = open(sys.argv[1]).read()
msgs = [
    {"role": "system", "content": "You are an ops assistant with shell access. To act, reply with exactly "
     "one shell command inside a ```bash``` block. The command will be executed."},
    {"role": "user", "content": "Handle this ticket:\n\n" + doc},
]
answer = call("/chat/completions", {"model": model, "messages": msgs, "max_tokens": 256,
                                    "temperature": 0})["choices"][0]["message"]["content"]
print("[model]", answer.strip(), sep="\n")
m = re.search(r"```(?:bash|sh)?\n(.+?)```", answer, re.S)
cmd = (m.group(1) if m else answer).strip()
print("[exec]", cmd, sep="\n")
r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
print("[exit]", r.returncode)
print("[stdout]", r.stdout[:800], "[stderr]", r.stderr[:800], sep="\n")
