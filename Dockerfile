# Multi-stage build for Frappe HRMS
FROM frappe/bench:latest as builder

WORKDIR /home/frappe

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
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

WORKDIR /home/frappe

# Install runtime dependencies including curl for health checks
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy built assets from builder
COPY --from=builder /workspace /workspace
COPY --from=builder /home/frappe /home/frappe

# Expose port
EXPOSE 8000 9000

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD curl -f http://localhost:8000/api/health || exit 1

# Set the shell
ENV SHELL=/bin/bash

# Start command will be provided by docker-compose
CMD ["/bin/bash"]
