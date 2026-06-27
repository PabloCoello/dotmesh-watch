# dotmesh watch face — build de Connect IQ.
# Requiere el Connect IQ SDK (monkeyc, monkeydo, connectiq) en el PATH y una
# developer key. La SDK no vive en este repo; compila donde la tengas instalada.

APP        := dotmesh
DEVICE     ?= epix2pro47mm
JUNGLE     := monkey.jungle
BUILD      := bin
KEY        := developer_key.der
PRG        := $(BUILD)/$(APP).prg
SRC        := $(wildcard source/*.mc)
RES        := $(shell find resources -type f 2>/dev/null)
GARMIN_DIR ?=

# Segunda app: approver (bridge/watchapp/). Comparte device y developer key.
APPR_APP      := dotmesh-approver
APPR_DIR      := bridge/watchapp
APPR_JUNGLE   := $(APPR_DIR)/monkey.jungle
APPR_MANIFEST := $(APPR_DIR)/manifest.xml
APPR_PRG      := $(BUILD)/$(APPR_APP).prg
APPR_SRC      := $(wildcard $(APPR_DIR)/source/*.mc)
APPR_RES      := $(shell find $(APPR_DIR)/resources -type f 2>/dev/null)

.PHONY: help build sim sideload key clean build-approver sim-approver sideload-approver

help:
	@echo "Targets:"
	@echo "  make key       genera developer_key.der si no existe"
	@echo "  make build     compila $(PRG) para $(DEVICE)"
	@echo "  make sim       lanza el simulador y carga la esfera"
	@echo "  make sideload  copia el .prg a un Garmin montado (GARMIN_DIR=/ruta/GARMIN)"
	@echo "  make clean     borra $(BUILD)/"
	@echo "  --- approver (bridge/watchapp) ---"
	@echo "  make build-approver     compila $(APPR_PRG)"
	@echo "  make sim-approver       lanza el simulador con el approver"
	@echo "  make sideload-approver  copia el approver a un Garmin montado"

# Clave de firma: idempotente, no se regenera si ya existe.
$(KEY):
	@command -v openssl >/dev/null 2>&1 || { echo "openssl no encontrado"; exit 1; }
	@echo "Generando developer key..."
	openssl genrsa -out developer_key.pem 4096
	openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out $(KEY) -nocrypt
	@echo "Listo: $(KEY) (ignorado por git)"

key: $(KEY)

build: $(PRG)

$(PRG): $(KEY) manifest.xml $(JUNGLE) $(SRC) $(RES)
	@command -v monkeyc >/dev/null 2>&1 || { echo "monkeyc no está en el PATH (instala el Connect IQ SDK)"; exit 1; }
	@mkdir -p $(BUILD)
	monkeyc -f $(JUNGLE) -o $(PRG) -y $(KEY) -d $(DEVICE) -w

sim: build
	@command -v connectiq >/dev/null 2>&1 || { echo "connectiq no está en el PATH (¿añadiste el SDK?)"; exit 1; }
	@if ! pgrep -x simulator >/dev/null 2>&1; then \
		echo "Abriendo el simulador..."; \
		( connectiq >/dev/null 2>&1 & ); \
		printf "Esperando al simulador"; \
		for i in 1 2 3 4 5 6 7 8; do pgrep -x simulator >/dev/null 2>&1 && break; printf "."; sleep 1; done; \
		echo; sleep 2; \
	fi
	monkeydo $(PRG) $(DEVICE)

# Copia a un reloj montado por USB/MTP:
#   make sideload GARMIN_DIR=/run/user/1000/gvfs/mtp.../GARMIN
# Detecta APPS/ o Apps/ (varía según firmware) y usa `gio copy` en montajes gvfs:
# por MTP el `cp` clásico falla ("operation not supported" al sobrescribir).
sideload: build
	@[ -n "$(GARMIN_DIR)" ] || { echo "Indica GARMIN_DIR=/ruta/al/GARMIN montado"; exit 1; }
	@dir=""; for d in "$(GARMIN_DIR)/APPS" "$(GARMIN_DIR)/Apps"; do [ -d "$$d" ] && dir="$$d"; done; \
	 [ -n "$$dir" ] || { echo "No encuentro APPS/ ni Apps/ en $(GARMIN_DIR) — ¿montado?"; exit 1; }; \
	 echo "Copiando $(PRG) -> $$dir/"; \
	 if command -v gio >/dev/null 2>&1 && case "$(GARMIN_DIR)" in */gvfs/*) true;; *) false;; esac; then \
	   gio remove "$$dir/$(APP).prg" 2>/dev/null || true; \
	   gio copy "$(PRG)" "$$dir/$(APP).prg"; \
	 else \
	   cp "$(PRG)" "$$dir/"; \
	 fi
	@echo "Copiada. Desconecta el reloj y selecciónala en la lista de esferas."

# --- approver (segunda app) ---
build-approver: $(APPR_PRG)

$(APPR_PRG): $(KEY) $(APPR_MANIFEST) $(APPR_JUNGLE) $(APPR_SRC) $(APPR_RES)
	@command -v monkeyc >/dev/null 2>&1 || { echo "monkeyc no está en el PATH (instala el Connect IQ SDK)"; exit 1; }
	@mkdir -p $(BUILD)
	monkeyc -f $(APPR_JUNGLE) -o $(APPR_PRG) -y $(KEY) -d $(DEVICE) -w

sim-approver: build-approver
	@command -v connectiq >/dev/null 2>&1 || { echo "connectiq no está en el PATH (¿añadiste el SDK?)"; exit 1; }
	@if ! pgrep -x simulator >/dev/null 2>&1; then \
		echo "Abriendo el simulador..."; \
		( connectiq >/dev/null 2>&1 & ); \
		printf "Esperando al simulador"; \
		for i in 1 2 3 4 5 6 7 8; do pgrep -x simulator >/dev/null 2>&1 && break; printf "."; sleep 1; done; \
		echo; sleep 2; \
	fi
	monkeydo $(APPR_PRG) $(DEVICE)

sideload-approver: build-approver
	@[ -n "$(GARMIN_DIR)" ] || { echo "Indica GARMIN_DIR=/ruta/al/GARMIN montado"; exit 1; }
	@dir=""; for d in "$(GARMIN_DIR)/APPS" "$(GARMIN_DIR)/Apps"; do [ -d "$$d" ] && dir="$$d"; done; \
	 [ -n "$$dir" ] || { echo "No encuentro APPS/ ni Apps/ en $(GARMIN_DIR) — ¿montado?"; exit 1; }; \
	 echo "Copiando $(APPR_PRG) -> $$dir/"; \
	 if command -v gio >/dev/null 2>&1 && case "$(GARMIN_DIR)" in */gvfs/*) true;; *) false;; esac; then \
	   gio remove "$$dir/$(APPR_APP).prg" 2>/dev/null || true; \
	   gio copy "$(APPR_PRG)" "$$dir/$(APPR_APP).prg"; \
	 else \
	   cp "$(APPR_PRG)" "$$dir/"; \
	 fi
	@echo "Copiada. Desconecta el reloj; el approver sale en la lista de apps."

clean:
	rm -rf $(BUILD)
