# Guia de Configuração

## Setup completo passo a passo

### 1. Supabase

1. Crie conta em [supabase.com](https://supabase.com)
2. Crie um novo projeto
3. Vá em **SQL Editor**
4. Cole e execute o conteúdo de `database/schema.sql`
5. Copie sua **Project URL** e **Service Role Key** em Settings → API

### 2. Gemini API

1. Acesse [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)
2. Clique em **Create API Key**
3. Copie a key (sem cartão de crédito necessário)

### 3. Apify

1. Crie conta em [apify.com](https://apify.com)
2. Vá em Account → Integrations
3. Copie seu **API Token**
4. O actor usado é: `web.harvester/twitter-scraper`

### 4. Telegram

1. Abra conversa com [@BotFather](https://t.me/BotFather)
2. Envie `/newbot` e siga as instruções
3. Copie o **token** do bot
4. Crie um grupo e adicione o bot
5. Envie uma mensagem no grupo
6. Acesse `https://api.telegram.org/bot<TOKEN>/getUpdates` pra pegar o **chat_id**

### 5. n8n

1. Crie conta em [app.n8n.cloud](https://app.n8n.cloud) ou use self-hosted
2. Configure as credentials:
   - **Supabase**: Host + Service Role Key
   - **Telegram**: Bot Token
3. Importe os dois workflows da pasta `workflows/`
4. Em cada workflow, atualize:
   - Token da Apify nos nodes HTTP Request
   - Gemini API Key nos nodes Code
   - Chat ID do Telegram
   - Selecione as colunas nos nodes Supabase
5. Teste manualmente antes de ativar o schedule

### Perfis monitorados

Adicione/remova perfis na tabela `source_profiles` do Supabase:

```sql
INSERT INTO source_profiles (username, display_name, niche) VALUES
  ('levelsio', 'Pieter Levels', 'ia_marketing'),
  ('sweatystartup', 'Nick Huber', 'growth');
```

### Troubleshooting

**Apify dá timeout:** O workflow usa chamada assíncrona (fire → wait 360s → fetch). Se o actor demorar mais, aumente o wait.

**Gemini corta a resposta:** Verifique se `thinkingBudget: 0` e `maxOutputTokens: 8192` estão configurados no node Code.

**Telegram rate limit:** O Workflow 1 envia apenas 1 mensagem resumo. Se ainda der rate limit, aumente o intervalo entre execuções.
