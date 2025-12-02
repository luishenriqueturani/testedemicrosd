#!/bin/bash

# --- Configurações ---
# O ponto de montagem (mount point) do seu cartão MicroSD. 
# **MUDE ESTE VALOR PARA O SEU PONTO DE MONTAGEM CORRETO!**
TARGET_DIR="/run/media/luis/microsd" 

# Nome e tamanho do arquivo de teste.
# 4.2G é um bom tamanho, como você sugeriu.
DUMMY_FILE_SIZE="4.2G"
DUMMY_FILE_NAME="teste_bloco_4g.bin"
DUMMY_FILE_PATH="$TARGET_DIR/$DUMMY_FILE_NAME"

# Variável para rastrear o número de cópias bem-sucedidas
COPY_COUNT=0

# --- Funções ---

# Função para limpar o disco (opcional, mas recomendado)
cleanup() {
    echo ""
    echo "🚨 Limpeza em andamento..."
    if [ -f "$DUMMY_FILE_PATH" ]; then
        rm -f "$DUMMY_FILE_PATH"
        echo "✅ Arquivo de bloco removido: $DUMMY_FILE_PATH"
    fi
    # Remove todos os arquivos com o padrão 'copia_XXX.bin'
    find "$TARGET_DIR" -name "copia_*.bin" -delete
    echo "✅ Arquivos de cópia removidos."
    echo "--- Teste finalizado. ---"
}

# Garante que a limpeza seja executada em caso de interrupção (Ctrl+C)
trap cleanup EXIT

# --- Início do Script ---

echo "🚀 Iniciando teste de capacidade do MicroSD..."
echo "Diretório alvo: $TARGET_DIR"
echo "Tamanho do bloco de teste: $DUMMY_FILE_SIZE"

# 1. Cria o arquivo de bloco
echo ""
echo "Criando o arquivo de bloco ($DUMMY_FILE_SIZE) com dd..."
if ! dd if=/dev/zero of="$DUMMY_FILE_PATH" bs=1M count=$((4200)) status=progress; then
    echo "❌ ERRO: Falha ao criar o arquivo de bloco. Verifique o ponto de montagem e permissões."
    exit 1
fi
echo "✅ Arquivo de bloco criado."

# 2. Loop de cópia
echo ""
echo "Iniciando loop de cópia para encher o disco..."
echo "Pressione Ctrl+C a qualquer momento para interromper."

# Loop infinito que só será interrompido por um erro de escrita (disco cheio)
while true; do
    COPY_COUNT=$((COPY_COUNT + 1))
    TARGET_COPY_NAME="$TARGET_DIR/copia_$COPY_COUNT.bin"

    echo ""
    echo "--- Cópia #$COPY_COUNT ---"
    
    # Tentativa de cópia
    if cp "$DUMMY_FILE_PATH" "$TARGET_COPY_NAME"; then
        echo "✅ Cópia $COPY_COUNT bem-sucedida. ($((COPY_COUNT * 4.2)) GB escritos)"
        
        # Opcional: Remova a cópia anterior para evitar que o espaço seja usado
        # A remoção permite que o teste continue a escrever no mesmo espaço físico, 
        # o que é mais eficaz para detectar chips falsos de "gravação lenta".
        if [ $COPY_COUNT -gt 1 ]; then
             rm -f "$TARGET_DIR/copia_$((COPY_COUNT - 1)).bin"
        fi
        
    else
        # Se o comando 'cp' falhar, provavelmente o disco está cheio.
        echo ""
        echo "========================================================="
        echo "🛑 ERRO DE ESCRITA! O disco provavelmente está cheio."
        echo "Última cópia bem-sucedida: #$((COPY_COUNT - 1))"
        # O valor real é o valor da última cópia bem-sucedida,
        # mais o tamanho do arquivo de bloco (que falhou ao ser copiado por último).
        REAL_CAPACITY_GB=$(awk "BEGIN {print (($COPY_COUNT - 1) * 4.2) + 4.2}")
        
        echo "CAPACIDADE REAL ESTIMADA: Aproximadamente ${REAL_CAPACITY_GB} GB"
        echo "========================================================="
        break # Sai do loop
    fi
done

# O trap 'EXIT' garantirá que a função cleanup() seja chamada aqui.