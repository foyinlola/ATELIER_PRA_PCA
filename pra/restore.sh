#!/bin/bash

echo "=== Backups disponibles ==="
kubectl -n pra exec \
  $(kubectl -n pra get pod -l app=flask -o jsonpath='{.items[0].metadata.name}') \
  -- ls -lht /backup
echo ""

echo "Entrez le nom du fichier à restaurer :"
read BACKUP_FILE

echo "⚠️  Restaurer $BACKUP_FILE ? (oui/non)"
read CONFIRM
if [ "$CONFIRM" != "oui" ]; then
  echo "Annulé."
  exit 1
fi

echo "🔥 Arrêt de l'application..."
kubectl -n pra scale deployment flask --replicas=0
kubectl -n pra patch cronjob sqlite-backup -p '{"spec":{"suspend":true}}'
kubectl -n pra delete job --all --ignore-not-found
kubectl -n pra delete pvc pra-data

echo "⏳ Recréation du PVC..."
kubectl apply -f k8s/10-pvc-data.yaml

echo "✅ Restauration depuis $BACKUP_FILE..."
sed "s/PLACEHOLDER/$BACKUP_FILE/" pra/51-job-restore-custom.yaml | kubectl apply -f -

echo "⏳ Attente fin du job..."
kubectl -n pra wait --for=condition=complete job/sqlite-restore-custom --timeout=60s

echo "🚀 Relance de l'application..."
kubectl -n pra scale deployment flask --replicas=1
kubectl -n pra patch cronjob sqlite-backup -p '{"spec":{"suspend":false}}'
kubectl -n pra delete job sqlite-restore-custom

echo ""
echo "✅ Restauration terminée !"
echo "👉 Re-forwarder le port :"
echo "kubectl -n pra port-forward svc/flask 8080:80 >/tmp/web.log 2>&1 &"