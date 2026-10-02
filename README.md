# SQL Proxy Menu

App de barra de menu do macOS para ligar e desligar o `cloud-sql-proxy` das instâncias Postgres do Cloud SQL, sem abrir terminal e sem renovar token na mão.

O app inicia cada proxy com `--auto-iam-authn`: o próprio proxy gera e renova o token IAM. A mls-api, o Beekeeper e qualquer outro cliente conectam em `127.0.0.1:<porta>` com o seu e-mail como usuário e **sem senha**.

## Requisitos

- macOS 13 (Ventura) ou superior
- Xcode Command Line Tools: `xcode-select --install`
- [`cloud-sql-proxy`](https://cloud.google.com/sql/docs/postgres/sql-proxy) v2: `brew install cloud-sql-proxy`
- Google Cloud SDK: `brew install --cask google-cloud-sdk`
- Credencial ADC: `gcloud auth application-default login`
- Acesso IAM às instâncias (veja [Permissões](#permissões))

## Instalação

```bash
git clone <url-do-repo> sql-proxy-menu
cd sql-proxy-menu
./install.sh
```

O script verifica os pré-requisitos, compila o app e instala em `~/Applications/SQL Proxy Menu.app`. Para atualizar, rode `git pull && ./install.sh`.

Para remover: `./uninstall.sh` (ou `./uninstall.sh --purge` para apagar também configuração e logs).

## Uso

O ícone de banco de dados fica na barra de menu, no canto superior direito. Ele não aparece no Dock.

| Ícone | Significado |
|---|---|
| cilindro vazado | nenhum proxy ligado |
| cilindro cheio + número | quantos proxies estão ligados |
| triângulo de alerta | a credencial do Google expirou |

- **Adicionar instância…** busca as instâncias Postgres de um projeto GCP (`gcloud sql instances list`) ou cadastra manualmente pelo connection name. As portas começam em **44515** (configurável em Preferências).
- **▶ / ■** liga e desliga cada proxy.
- **Copiar** copia a string de conexão, por exemplo `postgresql://nome%40empresa.com@127.0.0.1:44515/postgres`.
- **Clique direito** em uma instância: editar, ver logs, copiar connection name, remover.
- **Ver logs…** mostra a saída de cada proxy.
- **Preferências…** conta Google, caminho do `cloud-sql-proxy`, porta inicial, abrir ao iniciar sessão, notificações.

Quando a credencial do Google expira, o app avisa com uma notificação e um aviso no menu. **Reautenticar** abre o login do Google no navegador e reinicia os proxies que estavam ligados.

Ao sair do app, todos os proxies são encerrados. Se o app travar, os proxies órfãos são encerrados na próxima vez que ele abrir.

### Conectando

**Beekeeper Studio / DBeaver / psql**

- Host: `127.0.0.1`
- Porta: a da instância (ex.: `44515`)
- Usuário: seu e-mail do Google (ex.: `nome@empresa.com`)
- Senha: vazia
- SSL: desligado (o proxy já criptografa a conexão até o Cloud SQL)

**mls-api (`.env`)**

```
DATABASE_URL=postgresql://nome%40empresa.com@127.0.0.1:44515/<banco>
```

## Permissões

Cada pessoa precisa, **uma vez**, de quem administra o GCP/banco:

1. Papéis IAM no projeto da instância:

   ```bash
   gcloud projects add-iam-policy-binding <PROJETO> \
     --member="user:nome@empresa.com" --role="roles/cloudsql.client"
   gcloud projects add-iam-policy-binding <PROJETO> \
     --member="user:nome@empresa.com" --role="roles/cloudsql.instanceUser"
   ```

2. Usuário IAM criado na instância (a instância precisa da flag `cloudsql.iam_authentication=on`):

   ```bash
   gcloud sql users create nome@empresa.com \
     --instance=<INSTANCIA> --type=cloud_iam_user --project=<PROJETO>
   ```

3. Permissões dentro do Postgres. Um usuário IAM novo não enxerga nenhuma tabela até receber GRANTs. Exemplo (ajuste ao que a pessoa deve poder fazer):

   ```sql
   GRANT CONNECT ON DATABASE <banco> TO "nome@email.com";
   GRANT USAGE ON SCHEMA public TO "nome@email.com";
   GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "nome@email.com";
   ALTER DEFAULT PRIVILEGES IN SCHEMA public
     GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "nome@email.com";
   ```

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| `Porta X já está em uso por outro processo` | Outro programa (ou um proxy aberto no terminal) usa a porta. Feche-o ou edite a porta da instância. |
| `password authentication failed` / `Cloud SQL IAM user authentication failed` | Falta o usuário IAM na instância ou o papel `cloudsql.instanceUser`. |
| Conecta, mas `permission denied for table …` | Faltam os GRANTs no Postgres. |
| Aviso de credencial expirada com frequência | Política de reautenticação do Google Workspace. Clique em Reautenticar. |
| `cloud-sql-proxy não encontrado` | Instale com Homebrew ou informe o caminho em Preferências. |

## Onde ficam os arquivos

| O quê | Onde |
|---|---|
| Configuração (instâncias e preferências) | `~/Library/Application Support/SQLProxyMenu/config.json` |
| Logs de cada proxy | `~/Library/Logs/SQLProxyMenu/<instância>.log` |

## Desenvolvimento

```bash
swift build                  # compila
./scripts/build-app.sh       # gera build/SQL Proxy Menu.app
```

O código fica em `Sources/SQLProxyMenu`:

| Arquivo | Responsabilidade |
|---|---|
| `App.swift` | Entrada do app, barra de menu e janelas |
| `AppModel.swift` | Estado, processos do proxy, credencial, cadastro |
| `Tools.swift` | Localiza e executa `gcloud` / `cloud-sql-proxy`, verifica portas |
| `Storage.swift` | Configuração, PIDs e arquivos de log |
| `Notifier.swift` | Notificações do macOS |
| `Views/` | Menu, adicionar/editar instância, logs, preferências |
