# Security

## Reporting a vulnerability

Please report a vulnerability privately, not in a public issue. On GitHub, open this repository's
**Security** tab, choose **Report a vulnerability**, and describe what you found: what it lets a
person do, the steps to reproduce it, and the version or commit you ran. A report made there is
visible only to you and the maintainers, and the discussion, a fix and a credit for you if you want
one happen in that same private advisory.

You will get an acknowledgement, and then a decision on whether it is in scope and how we will fix
it. Please give us the chance to ship a fix before you describe the problem in public.

## What is in scope

The three halves of the Toolkit, as this repository ships them:

- **The CLI**: the PowerShell module and its scripts.
- **The agent**: the FastAPI service in `agent/`, including the bridge that runs CLI verbs.
- **The web UI**: the React app in `web/`, and the Docker image built from it.

Out of scope: the contents of the sample hub under `samples/hub` (it is made-up data, written to
be read, and holds nothing real), a weakness in a dependency that has no effect on how the Toolkit
uses it (report that upstream), and anything that needs an attacker who already has your user
account on the machine, since the Toolkit acts with your own permissions.

Code scanning runs: CodeQL scans the web UI and the agent on every push to `main`, on every pull request and weekly, and its findings are in this repository's **Security** tab.

## The trust model, in two paragraphs

The Toolkit is tooling for one person's own machine, and it has no accounts or sign-in of its own.
That is why the boundary is where each half listens: the agent binds to the loopback address
(`127.0.0.1`) and nowhere else, the development server for the web UI listens on localhost, and the
Docker image publishes its port on the loopback only. A process on the same machine can reach them;
another machine cannot. Do not put the agent behind a proxy or publish its port to a network:
nothing in it would ask who is calling.

Everything that changes a card goes through the CLI. The agent's bridge runs only the verbs in the
CLI's own command table, passing parameters as arguments rather than as a command line, and answers
anything else with `rejected` without running it. The Toolkit reaches your tracker, a chat webhook
or a model API with the credentials already on your machine, and a secret such as a model key or a
webhook URL belongs in `.env` or the environment, never in a configuration file the Toolkit writes.
The full description, with the files that hold each part, is the "Trust model" section of
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md#trust-model).
