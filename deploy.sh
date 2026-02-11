#!/bin/bash

# Deployment script for Flutter Web Dashboard
# This script builds and deploys the dashboard to Firebase Hosting

set -e  # Exit on error

echo "🚀 Starting deployment process..."
echo ""

# Step 1: Get dependencies
echo "📦 Step 1: Getting Flutter dependencies..."
flutter pub get

# Step 2: Build for web
echo ""
echo "🔨 Step 2: Building Flutter web app (release mode)..."
flutter build web --release

# Step 3: Verify build
if [ ! -d "build/web" ]; then
    echo "❌ Error: build/web directory not found. Build failed!"
    exit 1
fi

echo "✅ Build successful!"
echo ""

# Step 4: Deploy Firestore Indexes
echo "🔥 Step 3: Deploying Firestore indexes..."
firebase deploy --only firestore:indexes

echo ""
echo "⏳ Note: Indexes may take 5-15 minutes to show 'Enabled' in Firebase Console"
echo ""

# Step 5: Deploy Hosting
echo "🌐 Step 4: Deploying web hosting..."
firebase deploy --only hosting:aafia-site

echo ""
echo "✅ Deployment complete!"
echo ""
echo "🌐 Your dashboard is live at:"
echo "   https://aafia-myappointment.web.app"
echo ""
echo "⚠️  Note: Functions deployment skipped (functions/index.js needs to be restored)"
echo "   To deploy functions later, run: firebase deploy --only functions"
echo ""
echo "📊 Check Firebase Console for deployment status:"
echo "   https://console.firebase.google.com/project/myappointment-6843e/hosting"
