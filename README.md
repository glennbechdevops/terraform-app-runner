# Infrastruktur som kode med Terraform og AWS App Runner

Når du er ferdig med denne oppgaven, vil du ha et repository som inneholder en Spring Boot-applikasjon. Hver gang du gjør en commit til main branch, vil GitHub Actions utføre følgende:

- Bygge et Docker-image og pushe det til ECR, både med en "latest"-tag og en spesifikk tag som matcher git commit.
- Bruke Terraform til å opprette AWS-infrastruktur, inkludert IAM-roller og en AWS App Runner-tjeneste.

I denne oppgaven skal vi gjøre en Docker-container tilgjengelig på internett ved hjelp av AWS App Runner. App Runner oppretter den nødvendige infrastrukturen for containeren, slik at du som utvikler kan fokusere på koden.


Vi skal også se nærmere på mer avanserte GitHub Actions. Eksempler på dette inkluderer:

- To jobber med avhengigheter mellom dem.
- Én jobb vil opprette infrastruktur med Terraform, mens den andre vil bygge Docker-container-imaget.
- Bruke Terraform i pipeline, der GitHub Actions kjører Terraform for oss.

## Lag en fork

Før du starter må du lage en fork av dette repoet i din GitHub-konto:

1. Klikk på "Fork"-knappen øverst til høyre på denne siden
2. Velg din egen GitHub-konto som destinasjon

## Start GitHub Codespaces

1. Gå til din fork av repositoriet på GitHub
2. Klikk på den grønne "Code"-knappen
3. Velg "Codespaces"-fanen
4. Klikk på "Create codespace on main"

GitHub Codespaces vil nå sette opp et komplett utviklingsmiljø i skyen med alle nødvendige verktøy installert.

## Konfigurer AWS CLI i Codespaces

Lag IAM Access Keys for din bruker i AWS Console, og konfigurer AWS CLI:

```bash
aws configure
# AWS Access Key ID: [din key]
# AWS Secret Access Key: [din secret]
# Default region name: eu-west-1
# Default output format: json
```

Test at det fungerer:
```bash
aws sts get-caller-identity
```

**NB:** Aldri commit AWS-nøkler til Git.

## Opprett ECR repository

Opprett et ECR-repository for å lagre Docker-imaget ditt:

```bash
aws ecr create-repository --repository-name <ditt-studentnavn> --region eu-west-1
```

Verifiser at repositoriet er opprettet i AWS Console under ECR-tjenesten, og noter deg:
- Repository URI (f.eks. `244530008913.dkr.ecr.eu-west-1.amazonaws.com/<ditt-studentnavn>`)
- Din AWS Account ID (12-sifret nummer)

## Slå på GitHub Actions for din fork

I din fork av dette repositoriet, velg "actions" for å slå på støtte for GitHub Actions i din fork.

<img width="1143" height="104" alt="image" src="https://github.com/user-attachments/assets/90366061-e213-4d24-a527-b012af6c36ff" />

### Lag Repository secrets

GitHub Actions trenger tilgang til AWS-nøklene dine for å kunne bygge og deploye. Legg inn AWS-nøklene som secrets i GitHub:

1. Gå til din fork på GitHub
2. Klikk på "Settings" → "Secrets and variables" → "Actions"
3. Klikk "New repository secret" og legg til:
   - Name: `AWS_ACCESS_KEY_ID`, Value: [din Access Key ID]
   - Name: `AWS_SECRET_ACCESS_KEY`, Value: [din Secret Access Key]


## Terraform med GitHub Actions

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
  # Also pushes a tag called "latest" to track the latest commit

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
          docker tag hello 244530008913.dkr.ecr.eu-west-1.amazonaws.com/<STUDENTNAVN>:$rev
          docker tag hello 244530008913.dkr.ecr.eu-west-1.amazonaws.com/<STUDENTNAVN>:latest
          docker push 244530008913.dkr.ecr.eu-west-1.amazonaws.com/<STUDENTNAVN>:$rev
          docker push 244530008913.dkr.ecr.eu-west-1.amazonaws.com/<STUDENTNAVN>:latest

  terraform:
    name: "Terraform"
    needs: build_docker_image
    runs-on: ubuntu-latest
    env:
      AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      AWS_REGION: eu-west-1
      IMAGE: 244530008913.dkr.ecr.eu-west-1.amazonaws.com/<STUDENTNAVN>:latest
      PREFIX: <STUDENTNAVN>
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

Når noen gjør en Git push til *main* branch, kjører vi ```terraform apply``` med et flag ```--auto-approve``` som gjør at Terraform ikke
spør om lov før den kjører.

```yaml
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve
```

 Vi kan da bruke ```needs``` for å lage en avhengighet mellom en eller flere jobber;

```yaml
  terraform:
    needs: build_docker_image
```

## Tilpass provider.tf 

I provider.tf filen finner du en referanse til Terraform sin state fil. Den må være unik for deg, så Terraform ikke blander ressurser 
med andre studenter som gjør øvingen. 
```
  backend "s3" {
    bucket = "pgr301-2024-terraform-state"
    key    = "<STUDENT-NAVN>/apprunner-a-new-state.state"
    region = "eu-west-1"
  }
```

## Tilpass workflow-filen til ditt repository

Erstatt `<STUDENTNAVN>` med ditt studentnavn (må matche ECR repository navn)

Dette må gjøres på følgende steder i workflow-filen:
- I `build_docker_image` jobben: docker login, docker tag og docker push kommandoene
- I `terraform` jobben: `IMAGE` og `PREFIX` environment variables

## Test

* Gjør en push til main branch i repositoryet.
* Sjekk at det er dukket opp to container images i ECR. En med en tag som matcher git commit, og en som heter "latest".
* Lag en Pull request og se at det bare ```plan``` kjøres.
Test PR




Dette er min test : )
Test PR
