FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && apt-get install -y git curl gh jq tmux
RUN curl -fsSL https://claude.ai/install.sh | bash

WORKDIR /workspace

COPY ralph-loop.sh /usr/local/bin/ralph-loop
RUN chmod +x /usr/local/bin/ralph-loop

# Default .ralph config — used when target repo has none
COPY .ralph/PROMPT.md /ralph-defaults/PROMPT.md
COPY .ralph/guardrails.md /ralph-defaults/guardrails.md

CMD ["/usr/local/bin/ralph-loop"]
