# Infrastruktur som kode med Terraform og AWS App runner

Når du er ferdig med denne oppgaven, vil du ha et repository som inneholder en Spring Boot-applikasjon. Hver gang du gjør en commit til main branch, vil GitHub Actions utføre følgende:

- Bygge et Docker-image og pushe det til ECR, både med en "latest"-tag og en spesifikk tag som matcher git commit.
- Bruke Terraform til å opprette AWS-infrastruktur, inkludert IAM-roller og en AWS App Runner-tjeneste.

I denne oppgaven skal vi gjøre en Docker-container tilgjengelig på internett ved hjelp av AWS App Runner. App Runner oppretter den nødvendige infrastrukturen for containeren, slik at du som utvikler kan fokusere på koden.


Vi skal også se nærmere på mer avanserte GitHub Actions. Eksempler på dette inkluderer:

- To jobber med avhengigheter mellom dem.
- Én jobb vil opprette infrastruktur med Terraform, mens den andre vil bygge Docker-container-imaget.
- Bruke Terraform i pipeline, der GitHub Actions kjører Terraform for oss.

## Lag en fork

Før du starter må du lage en fork av dette repoet i din GitHub konto:

1. Klikk på "Fork"-knappen øverst til høyre på denne siden
2. Velg din egen GitHub-konto som destinasjon

## Start GitHub Codespaces

1. Gå til din fork av repositoriet på GitHub
2. Klikk på den grønne "Code"-knappen
3. Velg "Codespaces"-fanen
4. Klikk på "Create codespace on main"

GitHub Codespaces vil nå sette opp et komplett utviklingsmiljø i skyen med alle nødvendige verktøy installert.

### Konfigurer Git i Codespaces

Når Codespaces har startet, åpne terminalen og konfigurer Git med ditt brukernavn og e-post:

```shell
git config --global user.name "ditt-github-brukernavn"
git config --global user.email "din-epost@example.com"
```

GitHub Codespaces er allerede autentisert mot GitHub, så du trenger ikke å opprette access tokens for Git-operasjoner.

## Slå på GitHub actions for din fork

I din fork av dette repositoriet, velg "actions" for å slå på støtte for GitHub actions i din fork.

![Alt text](img/7.png "3")

### Lag Repository secrets

* Lag AWS IAM Access Keys for din bruker.  
* Se på .github/workflows/pipeline.yaml - Vi gjør AWS hemmeligheter tilgjengelig for GitHub ved å legge til følgende kodeblokk i github actions workflow fila vår slik at terraform kan autentisere seg med vår identitet, og våre rettigheter.

```yaml
    env:
      AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      AWS_REGION: eu-west-1
```

## Terraform med GitHub actions

Kopier følgende fil inn i katalogen .github/workflows/ - velg selv et passende navn 

```yaml
name: "Terraform"

on:
  push:
    branches:
      - main
  pull_request:

jobs:
  # Builds a new container image, and pushes it on every commit to the repository
  # Also pushes a tag called "latest" to track the lates commit

  build_docker_image:
    name: Push Docker image to ECR
    runs-on: ubuntu-latest
    steps:
      - name: Check out the repo
        uses: actions/checkout@v3

      - name: Build and push Docker image
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        run: |
          aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin 244530008913.dkr.ecr.eu-west-1.amazonaws.com
          rev=$(git rev-parse --short HEAD)
          docker build . -t hello
          docker tag hello 244530008913.dkr.ecr.eu-west-1.amazonaws.com/glenn:$rev
          docker tag hello 244530008913.dkr.ecr.eu-west-1.amazonaws.com/glenn:latest
          docker push 244530008913.dkr.ecr.eu-west-1.amazonaws.com/glenn:$rev
          docker push 244530008913.dkr.ecr.eu-west-1.amazonaws.com/glenn:latest

  terraform:
    name: "Terraform"
    needs: build_docker_image
    runs-on: ubuntu-latest
    env:
      AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      AWS_REGION: eu-west-1
      IMAGE: 244530008913.dkr.ecr.eu-west-1.amazonaws.com/glenn:latest
      PREFIX: glennbech3
 #    TF_LOG: trace
    steps:
      - uses: actions/checkout@v3
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2

      - name: Terraform Init
        id: init
        run: terraform init

      - name: Terraform Plan
        id: plan
        run: terraform plan   -var="prefix=$PREFIX" -var="image=$IMAGE"  -no-color
        continue-on-error: true

      - name: Terraform Plan Status
        if: steps.plan.outcome == 'failure'
        run: exit 1

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -var="prefix=$PREFIX" -var="image=$IMAGE"  -auto-approve
```


### Se over workflow filen - legg merke til følgende


Her ser vi et steg i en pipeline med en ```if``` - som bare skjer dersom det er en ```pull request``` som bygges, vi ser også at
pipeline får lov til å _fortsette dersom dette steget feiler.

```yaml
  - name: Terraform Plan
    id: plan
    if: github.event_name == 'pull_request'
    run: terraform plan -no-color
    continue-on-error: true
```

Når noen gjør en Git push til *main* branch, kjører vi ```terraform apply``` med ett flag ```--auto-approve``` som gjør at terraform ikke
spør om lov før den kjører.

```yaml
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve
```

Terraform trenger docker container som lages i en egen GitHub Actions jobb. Vi kan da bruke ```needs``` for å lage en avhengighet mellom en eller flere jobber;

```yaml
  terraform:
    needs: build_docker_image
```

## Opprett ditt eget ECR repository med Terraform

Du må opprette et ECR (Elastic Container Registry) repository for å lagre Docker-imaget ditt.

I katalogen `terraform-demo/` finner du et eksempel på hvordan du oppretter et ECR-repository med Terraform:

1. Se på filen `terraform-demo/ecr.tf` - dette er en enkel Terraform-konfigurasjon som oppretter et ECR-repository
2. Kjør følgende kommandoer fra `terraform-demo/` katalogen for å opprette ditt ECR-repository:

```bash
cd terraform-demo
terraform init
terraform apply -var="repo_name=<ditt-studentnavn>"
```

3. Gå til AWS Console og tjenesten ECR for å verifisere at repositoriet er opprettet
4. Kopier URI-en til ditt ECR-repository - du trenger denne i neste steg

## Gjør nødvendig endringer i pipeline.yml

Som dere ser er "glenn" og "244530008913.dkr.ecr.eu-west-1.amazonaws.com/glenn" hardkodet ganske mange steder. Du må erstatte dette med ditt eget ECR repository som du nettopp opprettet.

* Oppgave: Endre kodeblokken under slik at den *også* pusher en "latest" tag.

```sh
  docker build . -t hello
  docker tag hello 244530008913.dkr.ecr.eu-west-1.amazonaws.com/glenn:$rev
  docker push 244530008913.dkr.ecr.eu-west-1.amazonaws.com/glenn:$rev
  docker push 244530008913.dkr.ecr.eu-west-1.amazonaws.com/glenn:latest
```

## Endre terraform apply linjen

Finn denne linjen, du må endre prefix til å være ditt studentnavn, du må også legge inn studentnavn i image variabelen
for å fortelle app runner hvilket container som skal deployes.

```
 run: terraform apply -var="prefix=<studentnavn>" -var="image=244530008913.dkr.ecr.eu-west-1.amazonaws.com/<studentnavn>-private:latest" -auto-approve
```

## Test

* Kjør byggejobben manuelt førte gang gang. Det vil det lages en docker container som pushes til ECR repository. App runner vil lage en service
* Sjekk at det er dukket opp to container images i ECR. En med en tag som matcher git commit, og en som heter "latest".
* Lag en Pull request og se at det bare ````plan```` kjøres.
