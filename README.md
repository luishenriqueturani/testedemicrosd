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
3. **Verifica a integridade dos dados**: A partir da segunda cópia, o script verifica se a primeira cópia ainda está íntegra. Se os dados forem sobrescritos (indicando que o disco está realmente cheio), o teste é interrompido e a capacidade real é calculada
4. **Calcula a capacidade real** quando detectar sobrescrita de dados ou quando o disco estiver cheio
5. **Limpa automaticamente** todos os arquivos de teste ao final (ou ao pressionar Ctrl+C)

## Observações

- O teste pode demorar bastante tempo dependendo da velocidade do dispositivo
- Você pode interromper o teste a qualquer momento com `Ctrl+C` - a limpeza será feita automaticamente
- O script remove as cópias anteriores durante o teste para reutilizar o espaço físico, **exceto a primeira cópia**, que é mantida como referência para verificação de integridade
- **Verificação de sobrescrita**: O script detecta quando os dados começam a ser sobrescritos, o que indica que a capacidade real foi atingida. Isso é mais confiável do que apenas detectar erros de escrita
- Certifique-se de ter permissões de escrita no diretório de destino
