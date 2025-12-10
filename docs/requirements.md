O objetico deste projeto é criar uma imagem baseada no postgres 18 (alpine) que consiga usar o pgBackRest para realizar backup no S3 e ser capaz de restaura-lo.

Requisitos:

0. 100% compativel com drop-in-replacement da imagem oficial do postgre 18 (chamando entrypoint oficial)

1. o entrypoint principal da imagem deve ser capaz de:

- quando subir validar se a pasta atual do postgres ja existe com dados e subir normalmente o postgres
- se nao existe deve baixar (restore) o ultimo backup do s3 antes de iniciar o postgres (mostrando progresso conforme pgrestback suportar) e apos o download iniciar o postgres

2. a imagem deve ser capaz de gerar certificado de SSL caso nao existam em volume pre-informado, se certificando de sempre rodar no modo SSL

3. os backups devem ser feitos atraves de uma cron no proprio container

4. bando de dados pre-existentes criados pela imagem oficial do postgres 18 devem ser compativeis com essa imagem, e devem iniciar o backup imediatamente (caso a configuracao de backup seja informada)

5. devemos suportar backups full (semanais) diff (1x ao dia) e incr (a cada 30 minutos)

6. Configurar o PostgreSQL para enviar cada WAL fragmentado (archive_timeout) a cada 60s para que o pgbackrest envie para o s3 backups por minuto

7. a imagem deve ser capaz de ser uma replica ou um primary. uma replica deve ter o pb_basebackup ao iniciar e nao deve fazer backups pelo pgbackrest

8. Tudo deve vir de variaveis de ambientes passadas para o container

9. criar um docker compose com a stack pronto para uso

10. criar scripts para subir/gerar/hospedar a imagem docker no github ou atraves de github/actions workflow

11. criar gitignore e dockergnore e outros padroes dos repositorios git
