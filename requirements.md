O objetico deste projeto é criar uma imagem baseada no postgres 18 (alpine) que consiga usar o pgBackRest para realizar backup no S3 e ser capaz de restaura-lo.

Requisitos:

1. o entrypoint principal da imagem deve ser capaz de:

- quando subir validar se a pasta atual do postgres ja existe com dados e subir normalmente o postgres
- se nao existe deve baixar (restore) o ultimo backup do s3 antes de iniciar o postgres (mostrando progresso conforme pgrestback suportar) e apos o download iniciar o postgres

2. os backups devem ser feitos atraves de uma cron no proprio container

3. devemos suportar backups full (semanais) diff (1x ao dia) e incr (a cada 30 minutos)

4. Configurar o PostgreSQL para enviar cada WAL fragmentado (archive_timeout) a cada 60s para que o pgbackrest envie para o s3 backups por minuto

5. a imagem deve ser capaz de ser uma replica ou um primary

6. Tudo deve vir de variaveis de ambientes passadas para o container

7. criar um docker compose com a stack pronto para uso

8. criar scripts para subir/gerar/hospedar a imagem docker no github ou atraves de github/actions workflow
