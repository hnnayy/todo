import groovy.json.JsonSlurperClassic 

// --- HELPER METHODS (Optimized for Memory) ---

@NonCPS
def extractHashFromResponse(String response) {
    def matcher = response =~ /"hash"\s*:\s*"([^"]+)"/
    if (matcher.find()) {
        return matcher.group(1)
    }
    return ""
}

@NonCPS
def cleanJsonString(String rawOutput) {
    // Cari kurung kurawal pembuka dan penutup untuk membuang log sampah Windows
    int firstBrace = rawOutput.indexOf('{')
    int lastBrace = rawOutput.lastIndexOf('}')

    if (firstBrace == -1 || lastBrace == -1) {
        return null
    }
    return rawOutput.substring(firstBrace, lastBrace + 1)
}

@NonCPS
def generateHtmlSummary(String type, def jsonObj) {
    // Kita ambil data seperlunya saja agar ringan
    def score = jsonObj.security_score ?: 0
    def appName = jsonObj.app_name ?: "Unknown"
    def version = jsonObj.version_name ?: "1.0"
    
    def scoreColor = score < 50 ? '#e74c3c' : (score < 75 ? '#f39c12' : '#27ae60')

    return """
    <html>
    <head>
        <style>
            body { font-family: sans-serif; padding: 20px; background: #f0f0f0; }
            .card { background: white; padding: 30px; border-radius: 8px; max-width: 600px; margin: auto; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
            h1 { border-bottom: 2px solid #eee; color: #333; }
            .score { font-size: 50px; font-weight: bold; color: ${scoreColor}; text-align: center; margin: 20px 0; }
            table { width: 100%; border-collapse: collapse; margin-top: 20px; }
            td, th { padding: 10px; border-bottom: 1px solid #ddd; text-align: left; }
            .note { margin-top: 20px; font-size: 0.9em; color: #666; }
        </style>
    </head>
    <body>
        <div class="card">
            <h1>${type.toUpperCase()} Report Summary</h1>
            <div class="score">${score}/100</div>
            <table>
                <tr><th>App Name</th><td>${appName}</td></tr>
                <tr><th>Version</th><td>${version}</td></tr>
                <tr><th>Scan Type</th><td>${type.toUpperCase()}</td></tr>
            </table>
            <div class="note">
                <p><b>Note:</b> Full details are in the attached <b>${type}_report.json</b>.</p>
                <p><i>Tip: Open the JSON file in VS Code or a Browser to view it formatted.</i></p>
            </div>
        </div>
    </body>
    </html>
    """
}
// -----------------------------------------------------------------------

pipeline {
    agent any

    environment {
        ANDROID_HOME = "C:\\Users\\SECULAB\\AppData\\Local\\Android\\Sdk"
        PATH = "${env.ANDROID_HOME}\\tools;${env.ANDROID_HOME}\\platform-tools;${env.PATH}"
        AVD_NAME = "Pixel_4_XL_2"
        APP_PACKAGE = "com.example.mobileapp"
        APK_OUTPUT_DIR = "C:\\ApksGenerated"
    }

    stages {
        stage('Checkout') {
            steps {
                echo 'Starting Checkout stage'
                git branch: 'main',
                    url: 'https://github.com/hnnayy/todo.git',
                    credentialsId: 'github-pat-global-test'
            }
        }

        stage('Prepare Folders') {
            steps {
                bat 'if not exist apk-outputs mkdir apk-outputs'
                bat "if not exist \"${env.APK_OUTPUT_DIR}\" mkdir \"${env.APK_OUTPUT_DIR}\""
                bat "del /Q \"${env.APK_OUTPUT_DIR}\\*\"" 
            }
        }

        stage('Build Application') {
            steps {
                echo 'Starting Build Application stage'
                bat 'git config --global --add safe.directory C:/flutter'
                bat 'flutter pub get'
                bat 'flutter build apk --debug'
            }
        }

        // --- SAST STAGE ---
        stage('SAST Mobile') {
            steps {
                script {
                    echo 'Running SAST...'
                    
                    // 1. Upload
                    // Menggunakan @curl untuk menyembunyikan output command di log agar parsing lebih bersih
                    def uploadResponse = bat(script: '@curl -s -F "file=@build/app/outputs/flutter-apk/app-debug.apk" http://localhost:8000/api/v1/upload -H "Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac"', returnStdout: true).trim()
                    String apkHash = extractHashFromResponse(uploadResponse)
                    
                    if (apkHash == "") { error "Upload failed. Raw response: " + uploadResponse }
                    env.APK_HASH = apkHash
                    echo "SAST Hash: ${apkHash}"

                    // 2. Scan
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/scan --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // 3. Get JSON Report
                    def rawOutput = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/report_json --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // 4. Process Report (Memory Efficient)
                    try {
                        String jsonString = cleanJsonString(rawOutput)
                        
                        if (jsonString != null) {
                            // Simpan file JSON langsung (Tanpa Pretty Print di Memory) agar tidak OOM
                            writeFile file: 'sast_report.json', text: jsonString
                            
                            // Parse hanya untuk HTML summary
                            def slurper = new JsonSlurperClassic()
                            def jsonObj = slurper.parseText(jsonString)
                            def htmlContent = generateHtmlSummary("sast", jsonObj)
                            writeFile file: 'sast_summary.html', text: htmlContent
                        } else {
                            echo "WARNING: Failed to clean JSON output. Saving raw output."
                            writeFile file: 'sast_report_raw.txt', text: rawOutput
                        }
                    } catch (Exception e) {
                        echo "WARNING: Failed to process SAST report (likely too big for memory). Raw report saved."
                        // Tetap simpan raw output agar user bisa download
                        writeFile file: 'sast_report_error.json', text: rawOutput
                    }
                    
                    // Archive (Allow empty in case of severe error)
                    archiveArtifacts artifacts: 'sast_report.json, sast_summary.html, sast_report_raw.txt, sast_report_error.json', allowEmptyArchive: true
                }
            }
        }

        stage('Setup Emulator') {
            steps {
                script {
                    def devices = bat(script: "adb devices", returnStdout: true)
                    if (!devices.contains("emulator")) {
                        bat "start /b \"\" \"${env.ANDROID_HOME}\\emulator\\emulator.exe\" -avd \"${env.AVD_NAME}\" -no-window -no-audio -gpu swiftshader_indirect -wipe-data"
                        sleep(time: 60, unit: 'SECONDS')
                        bat "adb wait-for-device"
                    }
                    sleep(time: 15, unit: 'SECONDS')
                }
            }
        }

        stage('Install APK') {
            steps {
                script {
                    def timestamp = new Date().format("dd-MM-yyyy_HH-mm-ss")
                    bat "copy \"build\\app\\outputs\\flutter-apk\\app-debug.apk\" \"apk-outputs\\todo-debug-${timestamp}.apk\""
                    env.APK_PATH = "apk-outputs\\todo-debug-${timestamp}.apk"
                    bat(script: "adb uninstall ${env.APP_PACKAGE}", returnStatus: true) 
                    bat "adb install -r \"${env.APK_PATH}\""
                }
            }
        }

        // --- DAST STAGE ---
        stage('DAST Mobile') {
            steps {
                script {
                    echo 'Running DAST...'
                    
                    // Start
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/start_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    sleep(time: 40, unit: 'SECONDS') 

                    // Stop
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/stop_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // Get JSON Report
                    def rawOutput = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // Process Report (Memory Efficient)
                    try {
                        String jsonString = cleanJsonString(rawOutput)
                        
                        if (jsonString != null) {
                            writeFile file: 'dast_report.json', text: jsonString
                            
                            def slurper = new JsonSlurperClassic()
                            def jsonObj = slurper.parseText(jsonString)
                            def htmlContent = generateHtmlSummary("dast", jsonObj)
                            writeFile file: 'dast_summary.html', text: htmlContent
                        } else {
                            writeFile file: 'dast_report_raw.txt', text: rawOutput
                        }
                    } catch (Exception e) {
                        echo "WARNING: Failed to process DAST report. Saving raw."
                        writeFile file: 'dast_report_error.json', text: rawOutput
                    }

                    archiveArtifacts artifacts: 'dast_report.json, dast_summary.html, dast_report_raw.txt, dast_report_error.json', allowEmptyArchive: true
                }
            }
        }

        stage('Cleanup') {
            steps {
                bat 'adb emu kill'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'apk-outputs/*.apk', allowEmptyArchive: true
        }
    }
}