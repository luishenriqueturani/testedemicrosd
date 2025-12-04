#!/bin/bash

# --- Configurações ---
# O ponto de montagem (mount point) do seu cartão MicroSD.
TARGET_DIR="/run/media/luis/falso" 

# Tamanho do arquivo de teste em GB. Use bc para cálculos decimais.
DUMMY_FILE_SIZE_GB="2.2" 
# Tamanho em MB para o dd (aproximado).
DUMMY_FILE_SIZE_MB=$((2200)) 
DUMMY_FILE_NAME="teste_bloco_4g.bin"
DUMMY_FILE_PATH="$TARGET_DIR/$DUMMY_FILE_NAME"
TARGET_COPY_NAME_BASE="$TARGET_DIR/copia_"

# Variável para rastrear o número de cópias bem-sucedidas
COPY_COUNT=0

# Hash do arquivo original (será calculado após a criação)
ORIGINAL_FILE_HASH=""

# Pontos de verificação em GB (checkpoints)
FIRST_CHECKPOINT_GB=32  # Primeiro checkpoint em 32GB
CHECKPOINT_INTERVAL_GB=16  # Intervalo de verificação após 32GB
NEXT_CHECKPOINT_GB=$FIRST_CHECKPOINT_GB

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
    echo "Nota: Se o processo travar, pode ser um problema de I/O no dispositivo."
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
echo "Iniciando loop de cópia com verificação progressiva..."
echo "Primeiro checkpoint: ${FIRST_CHECKPOINT_GB}GB, depois a cada ${CHECKPOINT_INTERVAL_GB}GB"
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
        
        # 2b. Remove a cópia anterior, MAS SEMPRE MANTÉM:
        # - copia_1.bin (para verificação de integridade)
        # - copia_2.bin (backup adicional)
        # - copia atual e anterior (para ter pelo menos 2 cópias sempre)
        if [ $COPY_COUNT -gt 3 ]; then
            # Remove apenas cópias antigas, mantendo as 2 últimas e as 2 primeiras
            rm -f "$TARGET_COPY_NAME_BASE$((COPY_COUNT - 2)).bin"
        fi
        
        # 2c. *** TESTE DE INTEGRIDADE NOS CHECKPOINTS ***
        # Verifica integridade quando atingir os checkpoints progressivos
        SHOULD_CHECK=0
        
        # Verifica se atingimos ou passamos do próximo checkpoint
        if echo "$WRITTEN_GB >= $NEXT_CHECKPOINT_GB" | bc -l | grep -q 1; then
            SHOULD_CHECK=1
        fi
        
        if [ $SHOULD_CHECK -eq 1 ]; then
            echo ""
            echo "📊 CHECKPOINT ATINGIDO: ${WRITTEN_GB} GB escritos"
            echo "Verificando integridade dos arquivos originais..."
            safe_sync
            
            # Verifica se copia_1.bin ainda existe
            if [ ! -f "$TARGET_COPY_NAME_BASE1.bin" ]; then
                echo ""
                echo "========================================================="
                echo "🛑 ERRO CRÍTICO DE INTEGRIDADE DETECTADO!"
                echo "O arquivo 'copia_1.bin' foi deletado/sobrescrito pelo dispositivo."
                echo "Isso indica que a capacidade real foi atingida."
                echo ""
                
                # A capacidade real é aproximadamente o total escrito
                REAL_CAPACITY_GB=$(echo "scale=1; ($COPY_COUNT - 1) * $DUMMY_FILE_SIZE_GB" | bc)
                
                echo "CAPACIDADE REAL ESTIMADA: Aproximadamente ${REAL_CAPACITY_GB} GB"
                echo "CAPACIDADE REPORTADA: ${NEXT_CHECKPOINT_GB}+ GB (ou mais)"
                echo "DIFERENÇA: Cartão falsificado detectado!"
                echo "========================================================="
                break
            fi
            
            # Aguarda para garantir que o arquivo está acessível
            sleep 1
            
            # Calcula o hash da cópia #1 e compara com o hash original
            echo "Calculando hash de 'copia_1.bin'..."
            COPY1_HASH=$(md5sum "$TARGET_COPY_NAME_BASE1.bin" 2>/dev/null | cut -d' ' -f1)
            
            if [ -z "$COPY1_HASH" ]; then
                echo ""
                echo "========================================================="
                echo "🛑 ERRO CRÍTICO DE INTEGRIDADE DETECTADO!"
                echo "Não foi possível ler 'copia_1.bin'."
                echo "O arquivo pode ter sido corrompido ou sobrescrito."
                echo ""
                
                REAL_CAPACITY_GB=$(echo "scale=1; ($COPY_COUNT - 1) * $DUMMY_FILE_SIZE_GB" | bc)
                
                echo "CAPACIDADE REAL ESTIMADA: Aproximadamente ${REAL_CAPACITY_GB} GB"
                echo "Cartão falsificado detectado!"
                echo "========================================================="
                break
            fi
            
            if [ "$COPY1_HASH" != "$ORIGINAL_FILE_HASH" ]; then
                echo ""
                echo "========================================================="
                echo "🛑 ERRO CRÍTICO DE INTEGRIDADE DETECTADO!"
                echo "O arquivo 'copia_1.bin' foi corrompido/sobrescrito."
                echo ""
                echo "Hash original: ${ORIGINAL_FILE_HASH:0:16}..."
                echo "Hash da cópia: ${COPY1_HASH:0:16}..."
                echo ""
                
                REAL_CAPACITY_GB=$(echo "scale=1; ($COPY_COUNT - 1) * $DUMMY_FILE_SIZE_GB" | bc)
                
                echo "CAPACIDADE REAL ESTIMADA: Aproximadamente ${REAL_CAPACITY_GB} GB"
                echo "Cartão falsificado detectado!"
                echo "========================================================="
                break
            fi
            
            echo "✅ Integridade verificada. Arquivos originais estão OK (hash: ${COPY1_HASH:0:8}...)"
            
            # Atualiza o próximo checkpoint
            if echo "$NEXT_CHECKPOINT_GB == $FIRST_CHECKPOINT_GB" | bc -l | grep -q 1; then
                # Após o primeiro checkpoint, usa intervalos de 16GB
                NEXT_CHECKPOINT_GB=$(echo "$NEXT_CHECKPOINT_GB + $CHECKPOINT_INTERVAL_GB" | bc)
            else
                NEXT_CHECKPOINT_GB=$(echo "$NEXT_CHECKPOINT_GB + $CHECKPOINT_INTERVAL_GB" | bc)
            fi
            
            echo "Próximo checkpoint: ${NEXT_CHECKPOINT_GB} GB"
            echo "Continuando..."
            echo ""
        fi
        
    else
        # Se o comando 'cp' falhar, o disco está cheio.
        # Agora precisamos verificar se é um disco cheio real ou falso
        echo ""
        echo "⚠️  Erro ao copiar. O disco reporta estar cheio."
        echo "Última cópia bem-sucedida: #$((COPY_COUNT - 1))"
        
        LAST_SUCCESS_GB=$(echo "scale=1; ($((COPY_COUNT - 1)) * $DUMMY_FILE_SIZE_GB)" | bc)
        
        echo ""
        echo "Verificando integridade dos arquivos para determinar se o disco é real..."
        safe_sync
        sleep 2
        
        # Verifica se os primeiros arquivos ainda existem e estão íntegros
        if [ ! -f "$TARGET_COPY_NAME_BASE1.bin" ]; then
            echo ""
            echo "========================================================="
            echo "🛑 DISCO FALSIFICADO DETECTADO!"
            echo "O arquivo 'copia_1.bin' foi sobrescrito/deletado."
            echo ""
            echo "CAPACIDADE REAL: Aproximadamente ${LAST_SUCCESS_GB} GB"
            echo "Este é um cartão falsificado com capacidade menor que a reportada."
            echo "========================================================="
        else
            # Verifica a integridade
            COPY1_HASH=$(md5sum "$TARGET_COPY_NAME_BASE1.bin" 2>/dev/null | cut -d' ' -f1)
            
            if [ -n "$COPY1_HASH" ] && [ "$COPY1_HASH" = "$ORIGINAL_FILE_HASH" ]; then
                echo ""
                echo "========================================================="
                echo "✅ DISCO REAL CONFIRMADO!"
                echo "O disco está realmente cheio e os arquivos originais estão íntegros."
                echo ""
                echo "CAPACIDADE REAL: Aproximadamente ${LAST_SUCCESS_GB} GB"
                echo "Este é um cartão genuíno. A capacidade está correta."
                echo "========================================================="
            else
                echo ""
                echo "========================================================="
                echo "🛑 DISCO FALSIFICADO DETECTADO!"
                echo "O arquivo 'copia_1.bin' foi corrompido."
                echo ""
                if [ -n "$COPY1_HASH" ]; then
                    echo "Hash original: ${ORIGINAL_FILE_HASH:0:16}..."
                    echo "Hash da cópia: ${COPY1_HASH:0:16}..."
                fi
                echo ""
                echo "CAPACIDADE REAL: Aproximadamente ${LAST_SUCCESS_GB} GB"
                echo "Este é um cartão falsificado com capacidade menor que a reportada."
                echo "========================================================="
            fi
        fi
        
        break
    fi
done