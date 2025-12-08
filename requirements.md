O objetico deste projeto é criar uma imagem baseada no postgres 18 (alpine) que consiga usar o pgBackRest para realizar backup no S3 e ser capaz de restaura-lo

Requisitos:

1. o entrypoint principal da imagem deve ser capaz de:

- quando subir validar se a pasta atual do postgres ja existe com dados e subir normalmente o postgres
- se nao existe deve baixar (restore) o ultimo backup do s3 antes de iniciar o postgres (mostrando progresso conforme pgrestback suportar) e apos o download iniciar o postgres

2. os backups devem ser feitos atraves de uma cron no proprio container

3. a imagem deve ser capaz de ser uma replica ou um primary

4. Tudo deve vir de variaveis de ambientes passadas para o container

5. criar um docker compose com a stack pronto para uso
