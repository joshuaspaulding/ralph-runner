FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && apt-get install -y git curl gh jq tmux
RUN curl -fsSL https://claude.ai/install.sh | bash

WORKDIR /workspace

COPY ralph-loop.sh /usr/local/bin/ralph-loop
RUN chmod +x /usr/local/bin/ralph-loop

RUN mkdir -p /workspace/.ralph

VOLUME /workspace

CMD ["/usr/local/bin/ralph-loop"]
