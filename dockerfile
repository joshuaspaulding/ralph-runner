FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && apt-get install -y git curl gh jq tmux python3 python3-pip
RUN pip3 install anthropic --break-system-packages
RUN curl -fsSL https://claude.ai/install.sh | bash

WORKDIR /workspace

COPY ralph-loop.sh /usr/local/bin/ralph-loop
COPY ralph-agent.py /usr/local/bin/ralph-agent
RUN chmod +x /usr/local/bin/ralph-loop /usr/local/bin/ralph-agent

# Default .ralph config — used when target repo has none
COPY .ralph/PROMPT.md /ralph-defaults/PROMPT.md
COPY .ralph/guardrails.md /ralph-defaults/guardrails.md

CMD ["/usr/local/bin/ralph-loop"]
