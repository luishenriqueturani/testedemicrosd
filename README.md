# Teste de MicroSD

Script bash para testar a capacidade real de cartões MicroSD ou outros dispositivos de armazenamento, útil para detectar cartões falsificados que reportam capacidade maior do que realmente possuem.

## Como usar

### 1. Configuração

Antes de executar, edite o arquivo `teste_microsd.sh` e altere a variável `TARGET_DIR` na linha 6 para o ponto de montagem do seu dispositivo:

```bash
TARGET_DIR="/run/media/luis/microsd"  # Altere para o seu caminho
```

Para descobrir o ponto de montagem do seu dispositivo, use:
```bash
df -h
```
ou
```bash
lsblk
```

### 2. Execução

Torne o script executável (se necessário):
```bash
chmod +x teste_microsd.sh
```

Execute o script:
```bash
./teste_microsd.sh
```

### 3. O que o script faz

1. **Cria um arquivo de teste** de 4.2 GB no dispositivo
2. **Faz cópias sucessivas** deste arquivo até encher o disco
3. **Calcula a capacidade real** quando o disco estiver cheio
4. **Limpa automaticamente** todos os arquivos de teste ao final (ou ao pressionar Ctrl+C)

## Observações

- O teste pode demorar bastante tempo dependendo da velocidade do dispositivo
- Você pode interromper o teste a qualquer momento com `Ctrl+C` - a limpeza será feita automaticamente
- O script remove as cópias anteriores durante o teste para reutilizar o espaço físico, o que ajuda a detectar chips falsos com "gravação lenta"
- Certifique-se de ter permissões de escrita no diretório de destino
