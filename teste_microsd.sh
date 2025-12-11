#!/bin/bash

# --- Coleta de Parâmetros ---
# Aceita parâmetros: ./script.sh [PONTO_DE_MONTAGEM] [TAMANHO_GB]
# Se não fornecidos, pergunta ao usuário

# Função para validar se um número é válido (positivo e numérico)
is_valid_number() {
    local num="$1"
    # Verifica se é um número positivo (permite decimais)
    # Aceita formatos como: 1, 1.0, 0.5, 2.5, etc.
    # Rejeita: 0, 0.0, valores negativos, strings vazias
    if echo "$num" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        # Verifica se não é zero usando bc (se disponível) ou comparação simples
        if command -v bc >/dev/null 2>&1; then
            if [ "$(echo "$num > 0" | bc -l)" -eq 1 ]; then
                return 0
            fi
        else
            # Fallback: verifica se não é zero puro
            if [ "$num" != "0" ] && [ "$num" != "0.0" ] && [ "$num" != "0.00" ]; then
                return 0
            fi
        fi
    fi
    return 1
}

# Função para mostrar uso do script
show_usage() {
    echo "Uso: $0 [PONTO_DE_MONTAGEM] [TAMANHO_GB]"
    echo ""
    echo "Parâmetros:"
    echo "  PONTO_DE_MONTAGEM  - Diretório onde o dispositivo está montado (ex: /run/media/usuario/sd32)"
    echo "  TAMANHO_GB         - Tamanho do arquivo de teste em GB (ex: 1.0, 0.5, 2.0)"
    echo ""
    echo "Exemplos:"
    echo "  $0 /run/media/usuario/sd32 1.0"
    echo "  $0 /mnt/sdcard 0.5"
    echo "  $0  (será solicitado interativamente)"
}

# Verifica se o usuário pediu ajuda
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Coleta o ponto de montagem
if [ -n "$1" ]; then
    TARGET_DIR="$1"
else
    echo "📁 Informe o ponto de montagem do dispositivo MicroSD:"
    echo "   (ex: /run/media/usuario/sd32 ou /mnt/sdcard)"
    read -r TARGET_DIR
fi

# Remove barra final se houver
TARGET_DIR="${TARGET_DIR%/}"

# Valida o diretório
if [ -z "$TARGET_DIR" ]; then
    echo "❌ ERRO: Ponto de montagem não pode estar vazio."
    exit 1
fi

# Coleta o tamanho do arquivo de teste
if [ -n "$2" ]; then
    DUMMY_FILE_SIZE_GB="$2"
else
    echo ""
    echo "📏 Informe o tamanho do arquivo de teste em GB:"
    echo "   (ex: 1.0, 0.5, 2.0 - valores decimais são aceitos)"
    read -r DUMMY_FILE_SIZE_GB
fi

# Valida o tamanho
if [ -z "$DUMMY_FILE_SIZE_GB" ]; then
    echo "❌ ERRO: Tamanho do arquivo não pode estar vazio."
    exit 1
fi

if ! is_valid_number "$DUMMY_FILE_SIZE_GB"; then
    echo "❌ ERRO: Tamanho inválido. Deve ser um número positivo (ex: 1.0, 0.5, 2.0)"
    exit 1
fi

# Calcula o tamanho em MB (arredondado para inteiro)
# Converte GB para MB: 1 GB = 1000 MB
if ! DUMMY_FILE_SIZE_MB=$(echo "scale=0; ($DUMMY_FILE_SIZE_GB * 1000) / 1" | bc 2>/dev/null); then
    echo "❌ ERRO: Falha ao calcular tamanho. Verifique se 'bc' está instalado."
    exit 1
fi

# Valida se o resultado é válido
if [ -z "$DUMMY_FILE_SIZE_MB" ] || [ "$DUMMY_FILE_SIZE_MB" -le 0 ] 2>/dev/null; then
    echo "❌ ERRO: Tamanho calculado inválido: ${DUMMY_FILE_SIZE_MB} MB"
    exit 1
fi

# Gera o nome do arquivo baseado no tamanho
DUMMY_FILE_NAME="teste_bloco_${DUMMY_FILE_SIZE_GB}g.bin"
DUMMY_FILE_PATH="$TARGET_DIR/$DUMMY_FILE_NAME"
TARGET_COPY_NAME_BASE="$TARGET_DIR/copia_"

# Variável para rastrear o número de cópias bem-sucedidas
COPY_COUNT=0

# Hash do arquivo original (será calculado após a criação)
ORIGINAL_FILE_HASH=""

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

# Função para aguardar que os arquivos sejam acessíveis
# NOTA: Em dispositivos problemáticos, sync pode travar em estado 'D' (uninterruptible sleep)
# Por isso, não usamos sync, mas aguardamos que o arquivo esteja acessível
safe_sync() {
    # Aguarda um momento para o sistema processar I/O pendente
    # Aumentado para 2 segundos para dar tempo ao sistema de arquivos processar escritas
    sleep 2
}

# Função para tratamento de interrupção
interrupt_handler() {
    echo ""
    echo ""
    echo "⚠️  Interrupção detectada (Ctrl+C). Finalizando operações..."
    # NÃO executa sync aqui - pode travar. A limpeza será feita sem sync.
    cleanup
    exit 130  # Código de saída padrão para SIGINT
}

# Garante que a limpeza seja executada em caso de interrupção (Ctrl+C)
# Usa 'set -m' para permitir que jobs em background recebam sinais
trap interrupt_handler INT TERM
trap cleanup EXIT

# Permite que processos em background recebam sinais
set -m

# --- Início do Script ---

echo "🚀 Iniciando teste de capacidade do MicroSD com Verificação de Integridade..."
echo "Diretório alvo: $TARGET_DIR"
echo "Tamanho do bloco de teste: ${DUMMY_FILE_SIZE_GB}G"

# Verifica se o diretório existe e é gravável
if [ ! -d "$TARGET_DIR" ]; then
    echo "❌ ERRO: O diretório $TARGET_DIR não existe."
    echo "Verifique se o dispositivo está montado corretamente."
    exit 1
fi

if [ ! -w "$TARGET_DIR" ]; then
    echo "❌ ERRO: Sem permissão de escrita no diretório $TARGET_DIR."
    exit 1
fi

echo "✅ Diretório verificado e acessível."

# 1. Cria o arquivo de bloco
echo ""
echo "Criando o arquivo de bloco (${DUMMY_FILE_SIZE_GB}G) com dd..."
echo "Isso pode demorar alguns minutos. Pressione Ctrl+C para cancelar."
echo ""

# Tenta usar pv (pipe viewer) se disponível para mostrar progresso
if command -v pv >/dev/null 2>&1; then
    # Usa pv para mostrar progresso visual
    if ! (dd if=/dev/zero bs=1M count=$DUMMY_FILE_SIZE_MB 2>/dev/null | \
          pv -s ${DUMMY_FILE_SIZE_MB}M -p -t -e -r -b | \
          dd of="$DUMMY_FILE_PATH" bs=1M 2>/dev/null); then
        echo ""
        echo "❌ ERRO: Falha ao criar o arquivo de bloco. Verifique o ponto de montagem e permissões."
        exit 1
    fi
elif dd --help 2>/dev/null | grep -q "status=progress"; then
    # Usa status=progress se disponível (GNU coreutils)
    # Nota: Ctrl+C deve funcionar normalmente aqui
    if ! dd if=/dev/zero of="$DUMMY_FILE_PATH" bs=1M count=$DUMMY_FILE_SIZE_MB status=progress; then
        echo ""
        echo "❌ ERRO: Falha ao criar o arquivo de bloco. Verifique o ponto de montagem e permissões."
        exit 1
    fi
else
    # Fallback: dd simples sem progresso (mas mostra erros)
    echo "Aviso: Progresso não disponível. Aguarde..."
    echo "Nota: Se o processo travar, pode ser um problema de I/O no dispositivo. Neste ponto pode ser que o CTRL+C não funcione, pois o comando dd utilizado para criar o arquivo de testes bloqueie o processo, mas é questão de esperar ele finalizar para o processo ser cancelado."
    if ! dd if=/dev/zero of="$DUMMY_FILE_PATH" bs=1M count=$DUMMY_FILE_SIZE_MB; then
        echo ""
        echo "❌ ERRO: Falha ao criar o arquivo de bloco. Verifique o ponto de montagem e permissões."
        exit 1
    fi
fi

# Aguarda um momento para o sistema processar I/O pendente
# NOTA: sync foi removido pois pode travar em dispositivos com problemas de I/O
echo "Aguardando processamento de I/O..."
safe_sync
echo "✅ Pronto para continuar."

# Calcula o hash do arquivo original para verificação de integridade
echo "Calculando hash do arquivo original para verificação de integridade..."
ORIGINAL_FILE_HASH=$(md5sum "$DUMMY_FILE_PATH" | cut -d' ' -f1)
echo "✅ Arquivo de bloco criado. Hash: ${ORIGINAL_FILE_HASH:0:8}..."

# 2. Loop de cópia
echo ""
echo "Iniciando loop de cópia com verificação após cada escrita..."
echo "A integridade de TODOS os arquivos será verificada após cada nova cópia."
echo "Pressione Ctrl+C a qualquer momento para interromper."
echo ""

while true; do
    COPY_COUNT=$((COPY_COUNT + 1))
    TARGET_COPY_NAME="$TARGET_COPY_NAME_BASE$COPY_COUNT.bin"
    
    # Calcula o total escrito até agora
    WRITTEN_GB=$(echo "scale=1; $COPY_COUNT * $DUMMY_FILE_SIZE_GB" | bc)

    echo "--- Cópia #$COPY_COUNT (${WRITTEN_GB} GB acumulados) ---"
    
    # 2a. Tentativa de cópia
    if cp "$DUMMY_FILE_PATH" "$TARGET_COPY_NAME"; then
        
        echo "✅ Cópia $COPY_COUNT bem-sucedida."
        
        # NOTA IMPORTANTE: NÃO removemos NENHUM arquivo durante o teste!
        # Precisamos encher o disco completamente para:
        # - Cartão REAL: cp falhará quando realmente encher
        # - Cartão FALSO: continuará "copiando" mas sobrescreverá arquivos anteriores
        
        # 2b. *** VERIFICAÇÃO DE INTEGRIDADE DE TODOS OS ARQUIVOS ***
        # Aguarda processamento de I/O
        safe_sync
        
        echo "Verificando integridade de todos os arquivos copiados..."
        
        # Verifica todos os arquivos anteriores (de 1 até COPY_COUNT-1)
        # Se esta é a primeira cópia, não há nada para verificar ainda
        if [ $COPY_COUNT -gt 1 ]; then
            CORRUPTED_FILE=""
            CORRUPTED_NUM=0
            
            for i in $(seq 1 $((COPY_COUNT - 1))); do
                CHECK_FILE="${TARGET_COPY_NAME_BASE}${i}.bin"
                
                # Verifica se o arquivo existe
                if [ ! -f "$CHECK_FILE" ]; then
                    CORRUPTED_FILE="copia_${i}.bin"
                    CORRUPTED_NUM=$i
                    echo ""
                    echo "========================================================="
                    echo "🛑 Capacidade real atingida!"
                    echo "O arquivo '${CORRUPTED_FILE}' foi deletado/sobrescrito pelo dispositivo."
                    echo "Isso indica que a capacidade real foi atingida."
                    echo ""
                    
                    # A capacidade real é aproximadamente o total escrito menos o atual
                    REAL_CAPACITY_GB=$(echo "scale=1; ($COPY_COUNT - 1) * $DUMMY_FILE_SIZE_GB" | bc)
                    
                    echo "CAPACIDADE REAL ESTIMADA: Aproximadamente ${REAL_CAPACITY_GB} GB"
                    echo "CAPACIDADE REPORTADA: ${WRITTEN_GB} GB (ou mais)"
                    echo "DIFERENÇA: Cartão falsificado detectado!"
                    echo "========================================================="
                    break
                fi
                
                # Calcula o hash e compara
                FILE_HASH=$(md5sum "$CHECK_FILE" 2>/dev/null | cut -d' ' -f1)
                
                if [ -z "$FILE_HASH" ]; then
                    CORRUPTED_FILE="copia_${i}.bin"
                    CORRUPTED_NUM=$i
                    echo ""
                    echo "========================================================="
                    echo "🛑 Capacidade real atingida!"
                    echo "Não foi possível ler '${CORRUPTED_FILE}'."
                    echo "O arquivo pode ter sido corrompido ou sobrescrito."
                    echo ""
                    
                    REAL_CAPACITY_GB=$(echo "scale=1; ($COPY_COUNT - 1) * $DUMMY_FILE_SIZE_GB" | bc)
                    
                    echo "CAPACIDADE REAL ESTIMADA: Aproximadamente ${REAL_CAPACITY_GB} GB"
                    echo "Cartão falsificado detectado!"
                    echo "========================================================="
                    break
                fi
                
                if [ "$FILE_HASH" != "$ORIGINAL_FILE_HASH" ]; then
                    CORRUPTED_FILE="copia_${i}.bin"
                    CORRUPTED_NUM=$i
                    echo ""
                    echo "========================================================="
                    echo "🛑 Capacidade real atingida!"
                    echo "O arquivo '${CORRUPTED_FILE}' foi corrompido/sobrescrito."
                    echo ""
                    echo "Hash original: ${ORIGINAL_FILE_HASH:0:16}..."
                    echo "Hash da cópia: ${FILE_HASH:0:16}..."
                    echo ""
                    
                    REAL_CAPACITY_GB=$(echo "scale=1; ($COPY_COUNT - 1) * $DUMMY_FILE_SIZE_GB" | bc)
                    
                    echo "CAPACIDADE REAL ESTIMADA: Aproximadamente ${REAL_CAPACITY_GB} GB"
                    echo "Cartão falsificado detectado!"
                    echo "========================================================="
                    break
                fi
            done
            
            # Se detectou corrupção, para o teste
            if [ -n "$CORRUPTED_FILE" ]; then
                break
            fi
            
            echo "✅ Integridade verificada. Todos os $((COPY_COUNT - 1)) arquivos anteriores estão OK."
        fi
        
        echo ""
        
    else
        # Se o comando 'cp' falhar, o disco está cheio.
        # Agora precisamos verificar se é um disco cheio real ou falso
        echo ""
        echo "⚠️  Erro ao copiar. O disco reporta estar cheio."
        echo "Última cópia bem-sucedida: #$((COPY_COUNT - 1))"
        
        LAST_SUCCESS_GB=$(echo "scale=1; ($((COPY_COUNT - 1)) * $DUMMY_FILE_SIZE_GB)" | bc)
        
        echo ""
        echo "Verificando integridade de TODOS os arquivos para determinar se o disco é real..."
        safe_sync
        sleep 2
        
        # Verifica todos os arquivos copiados
        ALL_FILES_OK=1
        CORRUPTED_FILE=""
        
        for i in $(seq 1 $((COPY_COUNT - 1))); do
            CHECK_FILE="${TARGET_COPY_NAME_BASE}${i}.bin"
            
            # Verifica se o arquivo existe
            if [ ! -f "$CHECK_FILE" ]; then
                ALL_FILES_OK=0
                CORRUPTED_FILE="copia_${i}.bin"
                echo ""
                echo "========================================================="
                echo "🛑 Capacidade total atingida!"
                echo "O arquivo '${CORRUPTED_FILE}' foi sobrescrito/deletado."
                echo ""
                echo "CAPACIDADE REAL: Aproximadamente ${LAST_SUCCESS_GB} GB"
                echo "Este é um cartão falsificado com capacidade menor que a reportada."
                echo "========================================================="
                break
            fi
            
            # Verifica a integridade
            FILE_HASH=$(md5sum "$CHECK_FILE" 2>/dev/null | cut -d' ' -f1)
            
            if [ -z "$FILE_HASH" ] || [ "$FILE_HASH" != "$ORIGINAL_FILE_HASH" ]; then
                ALL_FILES_OK=0
                CORRUPTED_FILE="copia_${i}.bin"
                echo ""
                echo "========================================================="
                echo "🛑 Capacidade total atingida!"
                echo "O arquivo '${CORRUPTED_FILE}' foi corrompido."
                echo ""
                if [ -n "$FILE_HASH" ]; then
                    echo "Hash original: ${ORIGINAL_FILE_HASH:0:16}..."
                    echo "Hash da cópia: ${FILE_HASH:0:16}..."
                fi
                echo ""
                echo "CAPACIDADE REAL: Aproximadamente ${LAST_SUCCESS_GB} GB"
                echo "Este é um cartão falsificado com capacidade menor que a reportada."
                echo "========================================================="
                break
            fi
        done
        
        # Se todos os arquivos estão OK, é um disco real
        if [ $ALL_FILES_OK -eq 1 ]; then
            echo ""
            echo "========================================================="
            echo "✅ DISCO REAL CONFIRMADO!"
            echo "O disco está realmente cheio e TODOS os $((COPY_COUNT - 1)) arquivos estão íntegros."
            echo ""
            echo "CAPACIDADE REAL: Aproximadamente ${LAST_SUCCESS_GB} GB"
            echo "Este é um cartão genuíno. A capacidade está correta."
            echo "========================================================="
        fi
        
        break
    fi
done