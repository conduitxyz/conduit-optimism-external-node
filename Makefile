.PHONY: setup init up down logs status clean help

NETWORK ?=
ALTDA ?=

# Determine compose file based on ALTDA type
ifeq ($(ALTDA),celestia)
  COMPOSE_FILE := docker-compose.celestia.yml
  DOWNLOAD_FLAGS := --altda=celestia
else ifeq ($(ALTDA),eigenda)
  COMPOSE_FILE := docker-compose.eigenda.yaml
  DOWNLOAD_FLAGS := --altda=eigenda
else ifeq ($(ALTDA),)
  COMPOSE_FILE := docker-compose.yml
  DOWNLOAD_FLAGS :=
else
  $(error Unknown ALTDA value '$(ALTDA)'. Valid options: celestia, eigenda)
endif

help:
	@echo "Conduit Node Management"
	@echo ""
	@echo "Usage:"
	@echo "  make setup NETWORK=<slug>                 Setup standard OP Stack network"
	@echo "  make setup NETWORK=<slug> ALTDA=celestia  Setup Celestia DA network"
	@echo "  make setup NETWORK=<slug> ALTDA=eigenda   Setup EigenDA network"
	@echo ""
	@echo "Targets:"
	@echo "  setup    Download config and prepare op-reth"
	@echo "  init     Compatibility target; op-reth initializes on first start"
	@echo "  up       Start containers [ALTDA=celestia/eigenda]"
	@echo "  down     Stop containers [ALTDA=celestia/eigenda]"
	@echo "  logs     Show container logs"
	@echo "  status   Show sync status"
	@echo "  clean    Stop containers and remove data [ALTDA=celestia/eigenda]"
	@echo ""

setup: download init
	@echo "Setup complete!"

download:
ifndef NETWORK
	$(error NETWORK is required. Usage: make setup NETWORK=<slug>)
endif
	@echo "Downloading config for $(NETWORK)..."
	./download-config.sh $(DOWNLOAD_FLAGS) $(NETWORK)

init:
	@echo "op-reth does not require a separate init step; database initialization happens on first start."

up:
	@echo "Starting containers with $(COMPOSE_FILE)..."
	docker compose -f $(COMPOSE_FILE) up -d

down:
	docker compose -f $(COMPOSE_FILE) down

logs:
	docker compose -f $(COMPOSE_FILE) logs -f

status:
	./sync-status.sh

clean: down
	@echo "WARNING: This will permanently delete all node data in ./data"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || (echo "Aborted." && exit 1)
	@echo "Removing data directory..."
	rm -rf ./data
	@echo "Clean complete. Run 'make setup NETWORK=<slug>' to reinitialize."
