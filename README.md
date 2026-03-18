# 🔄 Content Repurposer Bot

Bot de automação que monitora posts de alta performance no X (Twitter), filtra por engajamento real, e automaticamente gera conteúdo adaptado para LinkedIn e blog SEO usando Gemini AI — tudo rodando no n8n com zero custo de infraestrutura.

A ideia é simples: os melhores posts do X já foram validados pelo mercado. Em vez de criar conteúdo do zero, o bot pega o que já funcionou, adapta pra outros formatos e te entrega pronto pra revisar e publicar.

## 🎯 O que faz

1. **Scraping automático** — Monitora perfis de referência no X a cada 6 horas e coleta tweets com alto engajamento via Apify
2. **Ranqueamento inteligente** — Calcula um engagement score ponderado que prioriza conteúdo que gera discussão, não só likes passivos
3. **Deduplicação** — Garante que o mesmo tweet nunca é processado duas vezes, mesmo entre execuções diferentes
4. **Repurposing com IA** — Gemini 2.5 Flash transforma cada tweet em:
   - Post LinkedIn completo em PT-BR (storytelling + CTA + hashtags)
   - Blog post SEO (800-1200 palavras, com título, meta description, headings e keywords)
   - Prompt de imagem em inglês pra geração visual com IA
5. **Notificação em tempo real** — Entrega tudo no Telegram pronto pra revisar e publicar

## 🏗️ Arquitetura

O sistema é dividido em dois workflows independentes que rodam em ciclos de 6 horas:

```
┌─────────────────────────────────────────────────────────────────┐
│  WORKFLOW 1: SCRAPING                                           │
│                                                                 │
│  Schedule (6h)                                                  │
│      │                                                          │
│      ▼                                                          │
│  Apify Twitter Scraper ──► Dispara scraping assíncrono          │
│      │                                                          │
│      ▼                                                          │
│  Aguarda 360s ──► Tempo pro Apify processar                     │
│      │                                                          │
│      ▼                                                          │
│  Busca Resultados ──► Coleta tweets do dataset                  │
│      │                                                          │
│      ▼                                                          │
│  Calcula Engagement ──► Score ponderado por tipo de interação   │
│      │                                                          │
│      ▼                                                          │
│  Filtra Score > 1.0 ──► Remove ruído e posts sem tração         │
│      │                                                          │
│      ▼                                                          │
│  Deduplica por tweet_id ──► Evita reprocessamento               │
│      │                                                          │
│      ▼                                                          │
│  Salva no Supabase ──► source_posts (is_processed = false)      │
│      │                                                          │
│      ▼                                                          │
│  Telegram ──► Resumo com top 3 tweets por score                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  WORKFLOW 2: REPURPOSING                                        │
│                                                                 │
│  Schedule (6h)                                                  │
│      │                                                          │
│      ▼                                                          │
│  Busca Posts Não Processados ──► is_processed = false            │
│      │                                                          │
│      ▼                                                          │
│  Gemini 2.5 Flash ──► Prompt estruturado com contexto           │
│      │                     do tweet + métricas de engajamento    │
│      ▼                                                          │
│  Parseia JSON ──► Extrai LinkedIn post + Blog post + Prompt     │
│      │                                                          │
│      ▼                                                          │
│  Salva Conteúdo ──► generated_content (status = draft)          │
│      │                                                          │
│      ▼                                                          │
│  Marca como Processado ──► is_processed = true                  │
│      │                                                          │
│      ▼                                                          │
│  Telegram ──► Preview do conteúdo gerado                        │
└─────────────────────────────────────────────────────────────────┘
```

A separação em dois workflows é intencional. O scraping é uma operação de I/O pesada (chamada assíncrona ao Apify com wait de 6 minutos), enquanto o repurposing é CPU-bound na API do Gemini. Separar os dois permite que falhas em um não afetem o outro, e facilita debugar problemas isoladamente.

## 🛠️ Stack

| Componente | Tecnologia | Por que essa escolha | Custo |
|---|---|---|---|
| Orquestração | n8n (Cloud ou self-hosted) | Visual, fácil de debugar, suporta webhooks e schedule | Grátis |
| Scraping | Apify — Twitter Scraper | Não precisa de API oficial do X, contorna rate limits | Free tier |
| IA (texto) | Google Gemini 2.5 Flash | Rápido, barato, bom com JSON estruturado, thinking desligável | Free tier (1500 req/dia) |
| Banco de dados | Supabase (PostgreSQL) | API REST automática, RLS, integração nativa com n8n | Free tier |
| Notificação | Telegram Bot API | Instantâneo, suporta Markdown, zero fricção pra checar no celular | Grátis |

**Custo total: R$0** — Todo o stack roda dentro dos free tiers. Pra um uso médio de ~20 tweets/dia processados, não chega nem perto dos limites.

## 📊 Sistema de Ranqueamento

O bot não pega qualquer tweet — ele calcula um **engagement score ponderado** que prioriza conteúdo com tração real.

### Fórmula

```
engagement_score = (likes × 1 + retweets × 2 + replies × 3) / 10
```

### Por que esses pesos?

| Métrica | Peso | Justificativa |
|---|---|---|
| **Likes** | ×1 | Interação passiva. A pessoa gostou, mas não agiu. É o sinal mais fraco de engajamento. |
| **Retweets** | ×2 | A pessoa quis compartilhar com a própria audiência. É uma validação social — ela tá colocando a reputação dela atrás daquele conteúdo. Peso dobrado porque indica que o conteúdo tem potencial viral. |
| **Replies** | ×3 | A pessoa parou o que tava fazendo pra escrever uma resposta. Isso indica que o conteúdo **gera discussão**, que é exatamente o tipo de conteúdo que funciona melhor pra repurposing — se as pessoas querem debater no X, vão querer debater no LinkedIn também. |

### Threshold e filtragem

- O filtro padrão é **score > 1.0**, o que significa que um tweet precisa de pelo menos ~10 likes ou ~5 retweets ou ~3-4 replies (ou uma combinação) pra passar. Isso elimina tweets genéricos e ruído sem ser restritivo demais.
- O threshold é **configurável** via tabela `bot_config` no Supabase — basta atualizar o valor de `min_engagement_score` sem mexer nos workflows.

### Deduplicação

O sistema usa `tweet_id` como chave única. Antes de salvar qualquer tweet novo, o workflow consulta todos os `tweet_id` existentes no Supabase e faz um diff em memória. Isso garante que:

- O mesmo tweet nunca é processado duas vezes, mesmo se aparecer em múltiplas execuções do scraping
- Tweets de perfis que são scrapados repetidamente não geram duplicatas
- O volume de dados no banco cresce de forma controlada

## 🎯 Como Escolher Perfis pra Monitorar

A qualidade do output depende diretamente da qualidade dos perfis que você monitora. Alguns critérios que funcionam bem:

### Tamanho ideal: 10k-500k seguidores

- **Menos de 10k**: Engajamento geralmente é baixo demais pra ter dados significativos. O filtro de score vai cortar quase tudo.
- **10k-500k**: Sweet spot. Grandes o suficiente pra ter engajamento consistente, pequenos o suficiente pra ter conteúdo autêntico e opinativo (não templates corporativos).
- **Mais de 500k**: Funciona, mas o conteúdo tende a ser mais genérico e já foi amplamente visto. O valor de repurposing diminui.

### Tipo de conteúdo que funciona

- **Ideal**: Perfis que postam conteúdo **opinativo, com insights e experiências pessoais**. Tweets que começam com "Eu aprendi...", "A maioria das pessoas não sabe...", "O problema com X é..." — esse tipo de conteúdo se adapta naturalmente pra LinkedIn e blog.
- **Evite**: Perfis que só postam notícias, links ou threads longas. Notícias não funcionam pra repurposing (ficam datadas rápido) e threads longas perdem contexto quando processadas como tweets individuais.

### Mix estratégico de nichos

Monte sua lista com diversidade:
- **2-3 perfis do nicho principal** (ex: IA, marketing digital) — conteúdo core da sua audiência
- **1-2 perfis de nichos adjacentes** (ex: produtividade, empreendedorismo, growth) — traz perspectivas diferentes que enriquecem o conteúdo

### Idioma não é barreira

Perfis em inglês funcionam muito bem. O Gemini não faz tradução literal — ele **adapta** o conteúdo pro PT-BR, reescrevendo com storytelling e tom adequado pro LinkedIn brasileiro. O resultado final soa natural, não traduzido.

### Exemplos por nicho

| Nicho | Perfis | Por que funcionam |
|---|---|---|
| IA / Tech | @levelsio, @ZedNilm1 | Posts opinativos sobre construir com IA, experiências reais, sem hype |
| Marketing | @Manu_Sisti | Insights práticos de copywriting e estratégia de conteúdo |
| Growth / Business | @sweatystartup, @binghott | Conteúdo sobre escalar negócios, decisões práticas, mentalidade |

## 💰 Monetização

O bot não é só um projeto técnico — é uma **máquina de produção de conteúdo** que pode gerar receita real de várias formas.

### Como creator de conteúdo

**LinkedIn como canal principal:**
- Use o output do bot pra postar 1-2x por dia no LinkedIn de forma consistente. Consistência é o que constrói audiência — e o maior problema de 90% dos creators é justamente não conseguir manter a frequência
- O bot resolve isso: você recebe conteúdo pronto no Telegram, revisa em 5-10 minutos, personaliza com suas experiências, e publica. O trabalho pesado de pesquisa + redação já tá feito
- Com 3-6 meses de posts consistentes, é realista chegar a 5k-15k seguidores qualificados no LinkedIn

**Blog SEO como renda passiva:**
- Cada tweet processado gera um artigo de 800-1200 palavras otimizado pra SEO, com título, meta description, headings e keywords
- Publique num blog próprio (WordPress, Ghost, ou Substack) e monetize com:
  - **Google AdSense**: R$2-10 por 1000 visualizações, dependendo do nicho
  - **Marketing de afiliados**: Recomende ferramentas que você usa (n8n, Supabase, ferramentas de IA) com links de afiliado nos artigos
  - **Lead magnet**: Use o blog pra capturar emails e vender infoprodutos depois
- Com 50-100 artigos indexados (2-3 meses de bot rodando), o tráfego orgânico começa a ser significativo

**Escala com audiência:**
- Com audiência no LinkedIn + blog com tráfego, você tem base pra vender:
  - **Consultorias**: Cobra por hora pra ajudar empresas a implementar automações similares
  - **Infoprodutos**: Curso ou e-book sobre automação com IA, content marketing, ou o próprio stack que você usa
  - **Serviços de automação**: Monta o mesmo sistema pra outros creators ou empresas como serviço recorrente

### O diferencial competitivo

O bot te dá **consistência** — e consistência é o que separa quem constrói audiência de quem desiste em 2 semanas. Com conteúdo sendo gerado automaticamente a cada 6 horas, tu nunca fica sem pauta. O gargalo deixa de ser "o que postar" e passa a ser "qual dos 5 conteúdos prontos eu publico hoje".

## 🆓 Free Tier — Como Rodar Sem Gastar Nada

Todo o stack foi escolhido pra caber dentro dos free tiers. Aqui tá o breakdown detalhado de cada serviço:

### n8n

- **Self-hosted com Docker**: Grátis pra sempre, sem limite de workflows ou execuções. É a opção recomendada pra uso contínuo
- **n8n Cloud**: 14 dias de free trial. Bom pra testar rápido sem configurar infra
- **Alternativa gratuita**: Rode no Railway ou Render com plano free — deploy com um clique e suficiente pra esse projeto
- Se o free trial do n8n Cloud expirar, migre pra Docker local (o guia tá em `docs/setup.md`) ou use Railway free tier

### Apify

- **US$5/mês de crédito grátis** pra todo mundo
- O actor `web.harvester/twitter-scraper` custa ~US$0.01 por run com 10 tweets
- Com `maxItems: 5` por perfil (configuração atual) e 4 execuções/dia, o custo mensal fica em torno de US$1.20 — cabe folgado no free tier
- **Dica**: Se precisar economizar, reduza `maxItems` pra 2-3 ou aumente o intervalo do schedule pra 12h

### Google Gemini Flash

- **1500 requests/dia** no free tier (sem cartão de crédito)
- Processando 10-20 tweets por dia, você usa **menos de 2% do limite diário**
- Mesmo com picos de scraping, é praticamente impossível estourar o limite com esse volume
- O modelo `gemini-2.5-flash` é o mais eficiente em custo/performance — rápido, barato e excelente com JSON estruturado

### Supabase

- **500MB de banco de dados** + 1GB de storage no free tier
- Cada tweet salvo ocupa ~1KB. Cada conteúdo gerado ~5KB (por causa do blog post)
- Com ~30 registros/dia, você leva **mais de 2 anos** pra chegar em 500MB
- Na prática, não chega nem perto do limite em meses de uso

### Telegram

- **100% grátis**, sem limites práticos pra bots
- Rate limit de 30 mensagens/segundo — o bot envia no máximo 2-3 mensagens por execução
- Sem custo, sem cadastro especial, sem aprovação — cria o bot com o @BotFather e pronto

### Resumo de custos

| Serviço | Limite Free | Uso estimado/mês | % do limite |
|---|---|---|---|
| n8n (self-hosted) | Ilimitado | ~240 execuções | 0% |
| Apify | US$5/mês | ~US$1.20 | 24% |
| Gemini Flash | 1500 req/dia | ~20 req/dia | 1.3% |
| Supabase | 500MB | ~1MB/mês | 0.2% |
| Telegram | Ilimitado | ~480 msgs | 0% |

## 📁 Estrutura do repositório

```
content-repurposer-bot/
├── README.md
├── .gitignore
├── .env.example                     # Template de variáveis de ambiente
├── workflows/
│   ├── workflow-1-scraping.json     # Workflow de coleta e ranqueamento de tweets
│   └── workflow-2-repurposing.json  # Workflow de geração de conteúdo com Gemini
├── database/
│   └── schema.sql                   # Schema completo do Supabase (5 tabelas + RLS + indexes)
└── docs/
    └── setup.md                     # Guia de configuração passo a passo
```

## 🚀 Setup

### Pré-requisitos

- Conta no [n8n Cloud](https://app.n8n.cloud) ou instância self-hosted
- Conta no [Supabase](https://supabase.com)
- Conta no [Apify](https://apify.com)
- [Gemini API Key](https://aistudio.google.com/app/apikey) (grátis, sem cartão)
- Bot do Telegram via [@BotFather](https://t.me/BotFather)

### 1. Banco de dados

1. Crie um projeto no Supabase
2. Abra o SQL Editor
3. Cole e execute o conteúdo de `database/schema.sql` — cria 5 tabelas, indexes de performance e RLS
4. Adicione os perfis que deseja monitorar na tabela `source_profiles`

### 2. Variáveis de ambiente

Copie `.env.example` pra `.env` e preencha com suas credenciais:

```bash
cp .env.example .env
```

### 3. Workflows n8n

1. Importe `workflows/workflow-1-scraping.json` no n8n
2. Configure as credentials:
   - **Supabase**: Project URL + Service Role Key
   - **Telegram**: Bot Token do BotFather
3. Atualize o token da Apify no node HTTP Request (`YOUR_APIFY_TOKEN`)
4. Atualize o chat_id do Telegram (`YOUR_TELEGRAM_CHAT_ID`)
5. Importe `workflows/workflow-2-repurposing.json`
6. Configure as mesmas credentials + Gemini API Key no node Code (`YOUR_GEMINI_API_KEY`)
7. Ative ambos os workflows

### 4. Teste

1. Execute o Workflow 1 manualmente — deve coletar tweets e salvar no Supabase
2. Verifique a tabela `source_posts` no Supabase — deve ter registros com `is_processed = false`
3. Execute o Workflow 2 — deve gerar conteúdo e notificar no Telegram
4. Verifique a tabela `generated_content` — deve ter registros com `status = draft`

## 📊 Schema do Banco de Dados

### Tabelas

| Tabela | Propósito | Registros típicos |
|---|---|---|
| **source_profiles** | Perfis do X monitorados (username, niche, is_active) | 5-20 perfis |
| **source_posts** | Tweets coletados com métricas e score de engajamento | Cresce ~20-50/dia |
| **generated_content** | Conteúdo gerado: LinkedIn post, blog completo, image prompt | 1:1 com posts processados |
| **bot_config** | Configurações dinâmicas (thresholds, modelo, idioma, tom) | ~10 configs |
| **workflow_runs** | Log de execuções com contadores e status | 8 runs/dia (4 por workflow) |

### Indexes de performance

- `idx_source_posts_processed` — Partial index em `is_processed = false` pra queries rápidas no Workflow 2
- `idx_source_posts_engagement` — Score DESC pra ranking
- `idx_source_posts_scraped_at` — Ordenação cronológica
- `idx_generated_content_status` — Filtragem por status (draft, approved, published)

## 🔧 Workflows em detalhe

### Workflow 1: Scraping

```
Schedule (6h) → Apify Dispara Scraping → Aguarda 360s → Busca Resultados
→ Calcula Engagement → Filtra Score > 1.0 → Deduplica → Salva no Supabase
→ Monta Resumo (Top 3) → Notifica Telegram
```

- **Coleta assíncrona**: O Apify é chamado via HTTP POST (fire-and-forget), depois o workflow espera 360 segundos e busca os resultados do dataset. Isso evita timeout e permite processar scraping de múltiplos perfis
- **Engagement score**: Calculado com pesos diferenciados (likes ×1, retweets ×2, replies ×3) dividido por 10
- **Deduplicação em memória**: Carrega todos os `tweet_id` existentes do Supabase e faz diff com os novos antes de salvar
- **Notificação rica**: Mensagem no Telegram com total de tweets salvos + preview dos top 3 por score

### Workflow 2: Repurposing

```
Schedule (6h) → Busca Posts Não Processados → Filtra is_processed = false
→ Gemini Gera Conteúdo → Parseia JSON → Salva Conteúdo Gerado
→ Marca como Processado → Notifica Telegram
```

- **Prompt engenhado**: Envia o conteúdo do tweet + username + métricas de engajamento pro Gemini com instruções específicas de tom, formato e tamanho pra cada output
- **JSON estruturado**: O Gemini retorna um JSON com `linkedin_post`, `blog_post` e `image_prompt` — o parser limpa backticks e valida a estrutura
- **Thinking desligado**: `thinkingBudget: 0` no Gemini Flash pra respostas mais rápidas e determinísticas
- **Status draft**: Todo conteúdo é salvo como "draft" — a ideia é que você revise e personalize antes de publicar, não que publique automaticamente

## 📝 Exemplos de output

Abaixo estão exemplos reais de conteúdo gerado pelo bot a partir de um tweet sobre a armadilha de overengineering.

**Tweet original:**
> "Rented a 7-bedroom mansion on Airbnb. Wish I had just stayed at a simple hotel. More isn't always better." — @levelsio (2.4k likes, 890 RTs, 340 replies, score: 3.9)

---

### Post LinkedIn gerado (completo):

> Recentemente, me deparei com um relato que me fez repensar como tomamos decisões — nos negócios e na vida.
>
> Um empreendedor alugou uma mansão de 7 quartos pelo Airbnb pra uma viagem. A expectativa era de luxo e conforto. A realidade? Quartos demais pra limpar, cozinha industrial que ninguém usou, piscina que deu trabalho e ninguém aproveitou. No final, ele desejou ter ficado num hotel simples com room service.
>
> Isso me lembrou de quantas vezes a gente faz o mesmo nos negócios:
>
> - Contrata a ferramenta enterprise quando o plano básico resolvia
> - Constrói a arquitetura "escalável" antes de ter 100 usuários
> - Adiciona 15 features no MVP quando 3 seriam suficientes
>
> A verdade é que simplicidade não é limitação — é estratégia. Os melhores produtos que eu já usei fazem poucas coisas, mas fazem muito bem feito.
>
> Da próxima vez que você estiver tentado a escolher a opção "mais completa", pergunte: eu preciso de 7 quartos, ou um quarto bom já resolve?
>
> E você, já caiu na armadilha do overengineering? Conta nos comentários qual foi a sua "mansão Airbnb".
>
> #GestaoDeProjetos #Simplicidade #Empreendedorismo #Startups #LessIsMore

---

### Blog post gerado (estrutura completa):

> **Título:** A Armadilha da Mansão Airbnb: Por Que 'Menos é Mais' nos Negócios e na Vida
>
> **Meta description:** Descubra por que a simplicidade supera a grandiosidade nos negócios. Lições práticas sobre overengineering e como tomar decisões melhores.
>
> **Keywords:** overengineering, simplicidade nos negócios, menos é mais, gestão de projetos, MVP, tomada de decisão
>
> ## Introdução
> Uma história viral sobre uma mansão Airbnb revela uma lição que todo empreendedor deveria aprender...
>
> ## O Que Acontece Quando Escolhemos "Mais"
> Análise do viés de complexidade e por que gravitamos naturalmente pra opções mais elaboradas...
>
> ## A Síndrome do Overengineering nos Negócios
> Exemplos práticos: ferramentas enterprise desnecessárias, arquiteturas prematuras, MVPs inchados...
>
> ## Por Que Simplicidade é uma Vantagem Competitiva
> Casos de sucesso de empresas que venceram fazendo menos: Basecamp, Notion, Linear...
>
> ## Como Aplicar o "Menos é Mais" no Seu Dia a Dia
> Framework prático: antes de adicionar complexidade, pergunte "isso resolve um problema real?"...
>
> ## Conclusão
> CTA: "Revise seu projeto atual. Tem alguma 'mansão Airbnb' escondida nele?"

---

### Notificação Telegram (Workflow 1 — Scraping):

```
🔍 Scraping concluído!

📊 12 tweets novos salvos

🏆 Top 3 por engajamento:

👤 @levelsio
📝 Rented a 7-bedroom mansion on Airbnb. Wish I had just stayed at a simple ho...
⭐ Score: 3.9 | ❤️ 2400 | 🔄 890

👤 @sweatystartup
📝 Stop trying to automate everything. Some things are better done manually un...
⭐ Score: 2.1 | ❤️ 1100 | 🔄 340

👤 @ZedNilm1
📝 The best AI products I've seen this week aren't using GPT-4. They're using ...
⭐ Score: 1.8 | ❤️ 890 | 🔄 210
```

### Notificação Telegram (Workflow 2 — Repurposing):

```
✨ Conteúdo gerado!

📌 Post original:
Rented a 7-bedroom mansion on Airbnb. Wish I had just stayed at a simple hotel. More isn't always...

💼 LinkedIn:
Recentemente, me deparei com um relato que me fez repensar como tomamos decisões — nos negócios e na vida. Um empreendedor alugou uma mansão de 7 quartos...

📝 Blog: A Armadilha da Mansão Airbnb: Por Que 'Menos é Mais' nos Negócios e na Vida

🔗 https://x.com/levelsio/status/1234567890
```

## 🔮 Melhorias futuras

- [ ] Geração de imagem via Gemini Flash Image API (o prompt já é gerado, falta integrar)
- [ ] Publicação automática no LinkedIn via API
- [ ] Dashboard de analytics com métricas de engajamento original vs. performance do conteúdo gerado
- [ ] Suporte a mais fontes (Reddit, newsletters, RSS feeds)
- [ ] A/B testing de diferentes tons de copywriting no Gemini
- [ ] Workflow 3: Agendamento automático de publicação com buffer de conteúdo

## 👤 Autor

**Gabriel Alves**
- LinkedIn: [linkedin.com/in/biel-als](https://linkedin.com/in/biel-als)
- GitHub: [github.com/galvza](https://github.com/galvza)

## 📄 Licença

MIT
