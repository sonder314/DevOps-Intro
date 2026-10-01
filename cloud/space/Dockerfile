# syntax=docker/dockerfile:1.7

ARG QUICKNOTES_IMAGE=ghcr.io/sonder314/devops-intro/quicknotes:v0.1.0
FROM ${QUICKNOTES_IMAGE}

ENV ADDR=0.0.0.0:8080 \
    DATA_PATH=/data/notes.json \
    SEED_PATH=/app/seed.json

EXPOSE 8080
