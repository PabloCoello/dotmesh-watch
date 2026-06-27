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

.PHONY: help build sim sideload key clean

help:
	@echo "Targets:"
	@echo "  make key       genera developer_key.der si no existe"
	@echo "  make build     compila $(PRG) para $(DEVICE)"
	@echo "  make sim       lanza el simulador y carga la esfera"
	@echo "  make sideload  copia el .prg a un Garmin montado (GARMIN_DIR=/ruta/GARMIN)"
	@echo "  make clean     borra $(BUILD)/"

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
sideload: build
	@[ -n "$(GARMIN_DIR)" ] || { echo "Indica GARMIN_DIR=/ruta/al/GARMIN montado"; exit 1; }
	@[ -d "$(GARMIN_DIR)/APPS" ] || { echo "No existe $(GARMIN_DIR)/APPS — ¿está montado el reloj?"; exit 1; }
	cp $(PRG) "$(GARMIN_DIR)/APPS/"
	@echo "Copiada. Desmonta el reloj y selecciónala en la lista de esferas."

clean:
	rm -rf $(BUILD)
