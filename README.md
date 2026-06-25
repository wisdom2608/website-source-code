```yml
name: Build Push and Update K8s Manifests

on:
  push:
    branches:
      - main
    paths:
      - '**/*' # This will trigger whenever there are changes in any file in the repository
env:
  IMAGE_NAME: docker.io/${{ secrets.DOCKERHUB_USERNAME }}/website

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Source Repository
        uses: actions/checkout@v4

    #   - name: Generate Timestamp Tag
    #     id: vars
    #     run: |
    #       IMAGE_TAG=$(date -u +"%Y%m%d-%H%M%S")
    #       echo "IMAGE_TAG=$IMAGE_TAG" >> $GITHUB_OUTPUT
      - name: Generate Image Tag
        id: vars
        run: |
            echo "IMAGE_TAG=$(date +'%Y%m%d-%H%M%S')" >> "$GITHUB_OUTPUT"

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build Docker Image
        run: |
           docker build -t $IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }} .   

      - name: Push Docker Image
        run: |
          docker push $IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }}
    
    # -------------------------------------------------------------------------------------------------
    # The commented steps below build and push docker images with both timestap tag and latest tag
    # ------------------------------------------------------------------------------------------------

    #   - name: Build Docker Image
    #     run: |
    #       docker build \
    #         -t $IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }} \
    #         -t $IMAGE_NAME:latest \
    #          .
    #   - name: Push Docker Image
    #     run: |
    #       docker push $IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }}
    #       docker push $IMAGE_NAME:latest

      - name: Checkout Kubernetes Manifests Repository
        uses: actions/checkout@v4
        with:
          repository: wisdom2608/website-k8s-manifests
          token: ${{ secrets.MANIFESTS_REPO_TOKEN }}
          path: manifests
#----------------------------------------------------------------------------------
# Downloads and installs Kustomize because later steps use kustomize edit set image
#----------------------------------------------------------------------------------
      - name: Install Kustomize
        run: |
          VERSION=v5.7.1
      
          curl -L -o kustomize.tar.gz \
            https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${VERSION}/kustomize_${VERSION}_linux_amd64.tar.gz
      
          tar -xzf kustomize.tar.gz
          chmod +x kustomize
          sudo mv kustomize /usr/local/bin/
          kustomize version

#----------------------------------------------------------
# Show Base Image Tag in Deployment.yml File Before Update
#----------------------------------------------------------
      - name: Show Base Deployment Before Update
        run: |
          cat manifests/base/deployment.yml

#---------------------------------------
#  Update Base Deployment Image Tag
#---------------------------------------
      - name: Update Base Deployment Image Tag
        run: |
          sed -i "s|image: .*|image: $IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }}|g" manifests/base/deployment.yml


#----------------------------------------------------------
# Show Base Image Tag in Deployment.yml File After Update
#----------------------------------------------------------
      - name: Show Base Deployment After Update
        run: |
          cat manifests/base/deployment.yml

# ----------------------------------------------------------
# UPDATE BASE KUSTOMIZATION IMAGE TAG IN KUSTOMIZATION.YML
# ----------------------------------------------------------

      - name: Show Base Kustomization Before Update
        run: |
           cat manifests/base/kustomization.yml

      - name: Update Base Kustomization Image
        working-directory: manifests/base
        run: |
          kustomize edit set image docker.io/${{ secrets.DOCKERHUB_USERNAME }}/website=$IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }}

      - name: Show Base Kustomization After Update
        run: |
          cat manifests/base/kustomization.yml


# ----------------------------------------------------------
# UPDATE OVERLAY KUSTOMIZATION IMAGE TAGS IN KUSTOMIZATION.YML
# ----------------------------------------------------------
      - name: Update Overlay Image Tags
        run: |
          for env in dev staging prod; do
            echo "Updating $env"
            cd manifests/overlays/$env
            kustomize edit set image docker.io/${{ secrets.DOCKERHUB_USERNAME }}/website=$IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }}
            cat kustomization.yml
            cd -
          done

#---------------------------------
# Show Dev image tag befor update
#---------------------------------         
      - name: Show Dev Image Tag Before Update
        run: |
            cat manifests/overlays/dev/kustomization.yml

# #---------------------
# # Update Dev image tag
# #---------------------
#       - name: Update Dev Image Tag
#         working-directory: manifests/overlays/dev
#         run: |
#           kustomize edit set image \
#             docker.io/${{ secrets.DOCKERHUB_USERNAME }}/website=$IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }}

# #---------------------------------
# # Show Dev image tag after update.
# #---------------------------------         
#       - name: Show Dev Image Tag After Update
#         run: |
#             cat manifests/overlays/dev/kustomization.yml


# #-------------------------------------
# # Show Staging image tag befor update
# #------------------------------------- 
#       - name: Show Staging Image Tag Before Update
#         run: |
#             cat manifests/overlays/staging/kustomization.yml

# #-------------------------
# # Update Staging image tag
# #-------------------------
#       - name: Update Staging Image Tag
#         working-directory: manifests/overlays/staging
#         run: |
#           kustomize edit set image \
#             docker.io/${{ secrets.DOCKERHUB_USERNAME }}/website=$IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }}


#---------------
# Commit Changes.
#---------------

      - name: Commit Changes
        working-directory: manifests
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

          git add .
            if git diff --cached --quiet; then
            echo "No changes detected"
            exit 0
          fi
            git commit -m "Update website image tag to ${{ steps.vars.outputs.IMAGE_TAG }}"  

# -----------------------------------------------------------------------
#   Push changes: Pushes the updated manifests repository back to GitHub.
# -----------------------------------------------------------------------
      - name: Push Changes
        working-directory: manifests
        run: |
          git push origin main

```
**Argo CD Structure (Recommended)**

If using GitOps with Argo CD:

```bash
website-source-code
        │
        ▼
Docker Hub
        │
        ▼
website-k8s-manifests
        │
        ▼
Argo CD
        │
        ▼
Kubernetes Cluster
```

You would create three Argo CD Applications:

- Dev → overlays/dev
- Staging → overlays/staging
- Prod → overlays/prod

**Naming Convention**

```bash
GitHub Repositories

website-source-code
website-k8s-manifests
```

**Docker image**

```bash
docker.io/<dockerhub-user>/website
```

**Namespaces**

```bash
website-dev
website-staging
website-prod
```
This structure scales well, keeps application code separate from deployment configuration, and follows a standard GitOps workflow using Kustomize and Docker Hub.


**A common approach is to**:

 - Build and tag the Docker image with the Git commit SHA.
 - Push the image to Docker Hub.
 - Clone the manifests repository.
 - Update the image tag in all Kustomize overlays (dev, staging, prod) using kustomize edit set image.
 - Commit and push the changes back to the manifests repository.


```yaml
name: Build Push and Update K8s Manifests

on:
  push:
    branches:
      - main

env:
  IMAGE_NAME: docker.io/${{ secrets.DOCKERHUB_USERNAME }}/website

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Source Repository
        uses: actions/checkout@v4

      - name: Generate Timestamp Tag
        id: vars
        run: |
          IMAGE_TAG=$(date -u +"%Y%m%d-%H%M%S")
          echo "IMAGE_TAG=$IMAGE_TAG" >> $GITHUB_OUTPUT

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build Docker Image
         run: |
           docker build -t $IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }} .   

      - name: Push Docker Image
        run: |
          docker push $IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }}
    
    # -------------------------------------------------------------------------------------------------
    # The commented steps below build and push docker images with both timestap tag and latest tag
    # ------------------------------------------------------------------------------------------------

    #   - name: Build Docker Image
    #     run: |
    #       docker build \
    #         -t $IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }} \
    #         -t $IMAGE_NAME:latest \
    #          .
    #   - name: Push Docker Image
    #     run: |
    #       docker push $IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }}
    #       docker push $IMAGE_NAME:latest

      - name: Checkout Kubernetes Manifests Repository
        uses: actions/checkout@v4
        with:
          repository: my-org/website-k8s-manifests
          token: ${{ secrets.MANIFESTS_REPO_TOKEN }}
          path: manifests
#----------------------------------------------------------------------------------
# Downloads and installs Kustomize because later steps use kustomize edit set image
#----------------------------------------------------------------------------------
      - name: Install Kustomize
        run: |
          curl -sLo kustomize.tar.gz https://github.com/kubernetes-sigs/kustomize/releases/latest/download/kustomize_linux_amd64.tar.gz
          tar -xzf kustomize.tar.gz
          chmod +x kustomize
          sudo mv kustomize /usr/local/bin/

#---------------------------------
# Show Dev image tag befor update
#---------------------------------         
      - name: Show Dev Image Tag Before Update
        run: |
            cat manifests/overlays/dev/kustomization.yaml

#---------------------
# Update Dev image tag
#---------------------
      - name: Update Dev Image Tag
        working-directory: manifests/overlays/dev
        run: |
          kustomize edit set image \
            docker.io/${{ secrets.DOCKERHUB_USERNAME }}/website=$IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }}

#---------------------------------
# Show Dev image tag after update
#---------------------------------         
      - name: Show Dev Image Tag After Update
        run: |
            cat manifests/overlays/dev/kustomization.yaml


#-------------------------------------
# Show Staging image tag befor update
#------------------------------------- 
      - name: Show Staging Image Tag Before Update
        run: |
            cat manifests/overlays/staging/kustomization.yaml

#-------------------------
# Update Staging image tag
#-------------------------
      - name: Update Staging Image Tag
        working-directory: manifests/overlays/staging
        run: |
          kustomize edit set image \
            docker.io/${{ secrets.DOCKERHUB_USERNAME }}/website=$IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }}


#-------------------------------------
# Show Staging image tag after update
#-------------------------------------
      - name: Show Staging Image Tag After Update
        run: |
            cat manifests/overlays/staging/kustomization.yaml


#----------------------------------
# Show Prod image tag before update
#----------------------------------
      - name: Show Prod Image Tag after Update
        run: |
            cat manifests/overlays/prod/kustomization.yaml


#----------------------
# Update Prod Image Tag
#----------------------
      - name: Update Prod Image Tag
        working-directory: manifests/overlays/prod
        run: |
          kustomize edit set image \
            docker.io/${{ secrets.DOCKERHUB_USERNAME }}/website=$IMAGE_NAME:${{ steps.vars.outputs.IMAGE_TAG }}

#---------------------------------
# Show Prod image tag after update
#---------------------------------
      - name: Show Prod Image Tag after Update
        run: |
            cat manifests/overlays/prod/kustomization.yaml

#---------------
# Commit Changes
#---------------

      - name: Commit Changes
        working-directory: manifests
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

          git add .
# -----------------------------------------------------------------------------------------
# If no changes: No changes detected, workflow continues without creating an empty commit.
# -----------------------------------------------------------------------------------------
          if git diff --cached --quiet; then
            echo "No changes detected"
            exit 0
          fi

# -----------------------------------------------------------------------------------------
# If changes exist, git commit -m "Update website image tag to 20260621-145501"
# -----------------------------------------------------------------------------------------

          git commit -m "Update website image tag to ${{ steps.vars.outputs.IMAGE_TAG }}"

# -----------------------------------------------------------------------
#   Push changes: Pushes the updated manifests repository back to GitHub.
# -----------------------------------------------------------------------
      - name: Push Changes
        working-directory: manifests
        run: |
          git push origin main
```

You need to create three secrets in your GitHub repository and obtain the corresponding credentials.

1. Create DOCKERHUB_USERNAME

This is simply your Docker Hub username.

Example:

```bash
Username: johndoe
```

GitHub Secret:

```bash
Name: DOCKERHUB_USERNAME
Value: johndoe
```

2. Create DOCKERHUB_TOKEN
Step 1: Login to Docker Hub

Go to:

Step 2: Create an Access Token
Navigate to:
Account Settings → Personal Access Tokens

Step 3: Generate Token

Example:

```bash
Description: github-actions
Permissions: Read, Write, Delete
```

Docker Hub will generate a token like:

```bash
dckr_pat_xxxxxxxxxxxxxxxxxxxxxxxxx
```

Copy it immediately.

Step 4: Add to GitHub Secrets

In your source-code repository:

```bash
Settings
 └─ Secrets and variables
     └─ Actions
         └─ New repository secret
```

3. Create MANIFESTS_REPO_TOKEN

This token allows the *source-code repository* workflow to push commits into the Kubernetes manifests repository.

Step 1: Create a GitHub Personal Access Token

Go to:

GitHub Personal Access Tokens

Choose:
 ```bash
 Fine-grained personal access token
 ```


 Step 2: Configure Token

Example:

```bash
Token name:
github-actions-manifests

Expiration:
90 days (or No expiration if your policy allows)

Repository access:
Only select repositories

Repositories:
website-k8s-manifests
```

Step 3: Grant Permissions

For the manifests repository:

```bash
Contents:
Read and Write
```

That's typically sufficient.

Step 4: Generate Token

GitHub will produce something like:

```bash
github_pat_xxxxxxxxxxxxxxxxxxxxx
```
Step 5: Add as Repository Secret

In the **source-code repository**:

```bash
Settings
 └─ Secrets and variables
     └─ Actions
         └─ New repository secret
```
Create:

```bash
Name: MANIFESTS_REPO_TOKEN
Value: github_pat_xxxxxxxxxxxxxxxxxxxxx
```

Final GitHub Secrets

In your website-source-code repository, you should have:


| Secret Name            | Example Value      |
| ---------------------- | ------------------ |
| `DOCKERHUB_USERNAME`   | `johndoe`          |
| `DOCKERHUB_TOKEN`      | `dckr_pat_xxxxx`   |
| `MANIFESTS_REPO_TOKEN` | `github_pat_xxxxx` |

...And it works 😂

