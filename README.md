# 🔄 Content Repurposer Bot

Bot de automação que monitora posts de alta performance no X (Twitter) sobre IA e Marketing, e automaticamente gera conteúdo adaptado para LinkedIn e blog SEO usando inteligência artificial.

## 🎯 O que faz

1. **Scraping automático** — Monitora perfis de referência no X e coleta tweets com alto engajamento
2. **Repurposing com IA** — Gemini Flash transforma cada tweet em:
   - Post LinkedIn completo em PT-BR (storytelling + CTA + hashtags)
   - Blog post SEO (800-1200 palavras, com título, meta description, headings e keywords)
3. **Notificação** — Entrega tudo no Telegram pronto pra revisar e publicar

## 🏗️ Arquitetura

```
Schedule (6h)
    │
    ▼
Apify Twitter Scraper ──► Scrapa tweets de 5 perfis
    │
    ▼
Filtro de Performance ──► Engagement score > threshold
    │
    ▼
Supabase ──► Deduplica + salva post original
    │
    ▼
Gemini Flash API ──► Gera LinkedIn post + Blog SEO
    │
    ▼
Supabase ──► Salva conteúdo gerado
    │
    ▼
Telegram ──► Notifica com resumo
```

## 🛠️ Stack

| Componente | Tecnologia | Custo |
|---|---|---|
| Orquestração | n8n (Cloud ou self-hosted) | Grátis |
| Scraping | Apify — Twitter Scraper | Free tier |
| IA (texto) | Google Gemini 2.5 Flash | Free tier (1500 req/dia) |
| Banco de dados | Supabase (PostgreSQL) | Free tier |
| Notificação | Telegram Bot API | Grátis |

**Custo total: R$0**

## 📁 Estrutura do repositório

```
content-repurposer-bot/
├── README.md
├── workflows/
│   ├── workflow-1-scraping.json       # Workflow de coleta de tweets
│   └── workflow-2-repurposing.json    # Workflow de geração de conteúdo
├── database/
│   └── schema.sql                     # Schema completo do Supabase
└── docs/
    └── setup.md                       # Guia de configuração
```

## 🚀 Setup

### Pré-requisitos

- Conta no [n8n Cloud](https://app.n8n.cloud) ou instância self-hosted
- Conta no [Supabase](https://supabase.com)
- Conta no [Apify](https://apify.com)
- [Gemini API Key](https://aistudio.google.com/app/apikey) (grátis)
- Bot do Telegram via [@BotFather](https://t.me/BotFather)

### 1. Banco de dados

1. Crie um projeto no Supabase
2. Abra o SQL Editor
3. Cole e execute o conteúdo de `database/schema.sql`
4. Adicione os perfis que deseja monitorar na tabela `source_profiles`

### 2. Workflows n8n

1. No n8n, importe `workflows/workflow-1-scraping.json`
2. Configure as credentials:
   - **Supabase**: Project URL + Service Role Key
   - **Telegram**: Bot Token do BotFather
3. Atualize o token da Apify no node HTTP Request
4. Atualize o chat_id do Telegram
5. Importe `workflows/workflow-2-repurposing.json`
6. Configure as mesmas credentials + Gemini API Key nos nodes Code
7. Ative ambos os workflows

### 3. Teste

1. Execute o Workflow 1 manualmente — deve coletar tweets e salvar no Supabase
2. Execute o Workflow 2 — deve gerar conteúdo LinkedIn + Blog e notificar no Telegram

## 📊 Schema do Banco de Dados

### Tabelas

- **source_profiles** — Perfis do X monitorados (username, niche, is_active)
- **source_posts** — Tweets coletados (content, engagement_score, is_processed)
- **generated_content** — Conteúdo gerado pela IA (linkedin_post, blog_title, blog_content, status)
- **bot_config** — Configurações dinâmicas do bot
- **workflow_runs** — Log de execuções

## 🔧 Workflows

### Workflow 1: Scraping

```
Schedule (6h) → Apify Dispara Scraping → Aguarda 360s → Busca Resultados
→ Calcula Engagement → Filtra Score Alto → Deduplica → Salva no Supabase
→ Resumo → Notifica Telegram
```

- Coleta assíncrona via Apify (fire → wait → fetch)
- Engagement score calculado: (likes + retweets×2 + replies×3) / 10
- Deduplicação por tweet_id
- Notificação com top 3 tweets no Telegram

### Workflow 2: Repurposing

```
Schedule (6h) → Busca Posts Não Processados → Gemini Gera Conteúdo
→ Parseia JSON → Salva Conteúdo Gerado → Marca como Processado
→ Notifica Telegram
```

- Gemini Flash gera JSON estruturado com LinkedIn + Blog + Image Prompt
- Parser robusto com fallback pra JSON malformado
- Conteúdo salvo com status "draft" pra revisão antes de publicar

## 📝 Exemplo de output

### Post LinkedIn gerado:

> Recentemente, me deparei com um tweet que revela uma verdade profunda sobre expectativa vs. realidade nos negócios. O autor lamentava ter alugado uma mansão de 7 quartos no Airbnb, desejando ter ficado num hotel simples...
>
> Essa anedota é um lembrete valioso: nem sempre mais é melhor. A simplicidade e a funcionalidade superam a grandiosidade que exige esforço desproporcional.
>
> #GestaoDeProjetos #Simplicidade #Empreendedorismo

### Blog post gerado:

> **A Armadilha da Mansão Airbnb: Por Que 'Menos é Mais' nos Negócios e na Vida**
>
> Artigo completo com ~1000 palavras, headings H2, exemplos práticos, conclusão com CTA e keywords SEO.

## 🔮 Melhorias futuras

- [ ] Geração de imagem via Gemini Flash Image API
- [ ] Publicação automática no LinkedIn via API
- [ ] Dashboard de analytics com métricas de engajamento
- [ ] Suporte a mais fontes (Reddit, newsletters, RSS)
- [ ] A/B testing de diferentes tons de copywriting

## 👤 Autor

**Gabriel Alves**
- LinkedIn: [linkedin.com/in/biel-als](https://linkedin.com/in/biel-als)
- GitHub: [github.com/galvza](https://github.com/galvza)

## 📄 Licença

MIT
