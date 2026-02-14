---
name: readme
description: Write documentation based on conversation history and folder contents
user-invocable: true
---

STARTER_CHARACTER = 📓

# Documentation Creation

Write markdown content based on the current conversation context and folder contents.


## Claude Skills

- use the /md-syntax skill for markdown rules and syntax
- use the /md-style skill for authoring conventions and writing style
- After writing, use /md-lint on the file to format and lint

Arguments: $ARGUMENTS

- First argument is the target file path. Additional text is guidance.
- If $ARGUMENTS is empty use README.md in the current directory as the file name
- Folder contents are at file argument level and below (siblings and subfolder), never above (parents)

## README.md Outline

Example document structure for README.md. Not required for non-readmes that might need a different structure.

```markdown
# Title

Brief overview. No more than five sentencies.

<!-- OPTIONAL IMAGE OR VIDEO HIGHLIGHT -->
<img src="somedemo.png" alt="Some Demo" width="800"/>

## Architecture

High level components and purpose

- Component - purpose
- Component - purpose

## Project Structure

Show folder structure. Don't include files.

\`\`\`text
davit/
├── src/
│   ├── davit-api/              # Go API server (k8s client) - see src/davit-api/README.md
│   ├── davit-ui/               # Go web UI server - see src/davit-ui/README.md
│   ├── davit-dinghy/           # Alpine dinghy container - see src/davit-dinghy/README.md
│   └── macos-proto-handler/    # macOS VSCode integration - see src/macos-proto-handler/README.md
├── scripts/                    # Build and deployment scripts
└── tests/                      # Test suites
\`\`\`

## Prerequisites

- Docker 20.10+ with BuildKit enabled (included by default)
- Kubernetes cluster - Local (Colima/Kind/Minikube) or remote
- kubectl 1.28+ - Configured for your cluster
- GNU Make 3.81+ - Build automation
- direnv 2.32+ - Environment variable management

## Installation

\`\`\`bash
# install manifest
kubectl apply manifest.yaml
\`\`\`

## Usage

\`\`\`bash
# Build all components
make all

# Or build individually
make build-api
make build-dinghy
\`\`\`

## Testing (optional if tests present)

\`\`\`bash
# Run all tests (placeholder)
make test

# Run specific test suites
make test-api
make test-pod
make test-integration
\`\`\`

## Contributing (optional it CONTRIBUTING.md present)

## Acknowledgements (optional)

## License (optional if LICENSE present)

```
