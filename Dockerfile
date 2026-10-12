# Multi-stage build for Frappe HRMS
FROM frappe/bench:latest as builder

USER root

WORKDIR /home/frappe

# Fix apt-get permission issue and install dependencies
RUN rm -rf /var/lib/apt/lists/* && \
    apt-get clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy app files
COPY . /workspace

# Build frontend assets
RUN cd /workspace && \
    if [ -d "frontend" ]; then \
      cd frontend && yarn install --check-files && yarn build; \
    fi && \
    if [ -d "roster" ]; then \
      cd roster && yarn install --check-files && yarn build; \
    fi

# Production stage
FROM frappe/bench:latest

USER root

WORKDIR /home/frappe

# Fix apt-get permission issue and install runtime dependencies including curl for health checks
RUN rm -rf /var/lib/apt/lists/* && \
    apt-get clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy built assets from builder
COPY --from=builder /workspace /workspace
COPY --from=builder /home/frappe /home/frappe

# Keep the entrypoint outside the bench volume mount.
COPY frappe-start.sh /home/frappe/frappe-start.sh
RUN chmod 755 /home/frappe/frappe-start.sh \
    && chown frappe:frappe /home/frappe/frappe-start.sh

# Expose port
EXPOSE 8000 9000

# Frappe answers /api/method/ping. First boot installs ERPNext, so allow a long start.
HEALTHCHECK --interval=30s --timeout=10s --retries=10 --start-period=3600s \
    CMD curl -fsS http://127.0.0.1:8000/api/method/ping || exit 1

ENV SHELL=/bin/bash

CMD ["bash", "/home/frappe/frappe-start.sh"]
