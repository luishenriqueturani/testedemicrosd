#!/bin/bash

# --- Configurações ---
# O ponto de montagem (mount point) do seu cartão MicroSD.
TARGET_DIR="/run/media/luis/microsd" 

# Tamanho do arquivo de teste em GB. Use bc para cálculos decimais.
DUMMY_FILE_SIZE_GB="4.2" 
# Tamanho em MB para o dd (aproximado).
DUMMY_FILE_SIZE_MB=$((4200)) 
DUMMY_FILE_NAME="teste_bloco_4g.bin"
DUMMY_FILE_PATH="$TARGET_DIR/$DUMMY_FILE_NAME"
TARGET_COPY_NAME_BASE="$TARGET_DIR/copia_"

# Variável para rastrear o número de cópias bem-sucedidas
COPY_COUNT=0

# --- Funções ---

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

echo "🚀 Iniciando teste de capacidade do MicroSD com Verificação de Integridade..."
echo "Diretório alvo: $TARGET_DIR"
echo "Tamanho do bloco de teste: ${DUMMY_FILE_SIZE_GB}G"

# 1. Cria o arquivo de bloco
echo ""
echo "Criando o arquivo de bloco (${DUMMY_FILE_SIZE_GB}G) com dd..."
# O status=progress é removido aqui para garantir compatibilidade com o redirecionamento de erro.
if ! dd if=/dev/zero of="$DUMMY_FILE_PATH" bs=1M count=$DUMMY_FILE_SIZE_MB 2>/dev/null; then
    echo "❌ ERRO: Falha ao criar o arquivo de bloco. Verifique o ponto de montagem e permissões."
    exit 1
fi
echo "✅ Arquivo de bloco criado."

# 2. Loop de cópia
echo ""
echo "Iniciando loop de cópia e verificação para encher o disco..."
echo "Pressione Ctrl+C a qualquer momento para interromper."

while true; do
    COPY_COUNT=$((COPY_COUNT + 1))
    TARGET_COPY_NAME="$TARGET_COPY_NAME_BASE$COPY_COUNT.bin"

    echo ""
    echo "--- Cópia #$COPY_COUNT ---"
    
    # 2a. Tentativa de cópia
    if cp "$DUMMY_FILE_PATH" "$TARGET_COPY_NAME"; then
        
        WRITTEN_GB=$(echo "scale=1; $COPY_COUNT * $DUMMY_FILE_SIZE_GB" | bc)
        echo "✅ Cópia $COPY_COUNT bem-sucedida. ($WRITTEN_GB GB escritos - Falsa Contagem)"
        
        # 2b. Opcional: Remova a cópia anterior, exceto a cópia #1
        # É CRUCIAL manter a Cópia #1 para o teste de integridade!
        if [ $COPY_COUNT -gt 2 ]; then
             rm -f "$TARGET_COPY_NAME_BASE$((COPY_COUNT - 1)).bin"
        fi
        
        # 2c. *** TESTE DE INTEGRIDADE ***
        # Começa a verificar a Cópia #1 a partir da Cópia #2. 
        # Esta é a condição que irá quebrar o loop assim que os dados forem sobrescritos.
        if [ $COPY_COUNT -ge 2 ]; then
            
            # O cmp compara o arquivo de bloco original com a Cópia #1.
            # Se a Cópia #1 foi sobrescrita, ela será diferente do original e o cmp falhará.
            if ! cmp -s "$DUMMY_FILE_PATH" "$TARGET_COPY_NAME_BASE1.bin"; then
                echo "========================================================="
                echo "🛑 ERRO CRÍTICO DE INTEGRIDADE DETECTADO!"
                echo "O arquivo 'copia_1.bin' foi sobrescrito/corrompido."
                
                # A capacidade real é o total escrito ANTES da cópia que causou a falha (i.e., COPY_COUNT - 1).
                REAL_CAPACITY_COPIES=$((COPY_COUNT - 1))
                LAST_SUCCESS_GB=$(echo "scale=1; $REAL_CAPACITY_COPIES * $DUMMY_FILE_SIZE_GB" | bc)
                
                echo "CAPACIDADE REAL ESTIMADA: Aproximadamente ${LAST_SUCCESS_GB} GB"
                echo "Isso significa que o chip físico tem ${LAST_SUCCESS_GB} GB, e a diferença é espaço falso."
                echo "========================================================="
                break # Sai do loop por falha de integridade
            fi
            
            echo "✅ Cópia #1 verificada. Integridade OK."
        fi
        
    else
        # Se o comando 'cp' falhar, provavelmente o disco está realmente cheio.
        echo ""
        echo "========================================================="
        echo "🛑 ERRO DE ESCRITA! O disco está realmente cheio."
        echo "Última cópia bem-sucedida: #$((COPY_COUNT - 1))"
        
        # Se chegou aqui, é um disco cheio real.
        LAST_SUCCESS_GB=$(echo "scale=1; ($((COPY_COUNT - 1)) * $DUMMY_FILE_SIZE_GB)" | bc)
        REAL_CAPACITY_GB=$(echo "scale=1; $LAST_SUCCESS_GB + $DUMMY_FILE_SIZE_GB" | bc)
        
        echo "CAPACIDADE REAL ESTIMADA: Aproximadamente ${REAL_CAPACITY_GB} GB"
        echo "========================================================="
        break
    fi
done