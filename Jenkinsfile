import groovy.json.JsonSlurperClassic 
import groovy.json.JsonOutput 

// --- HELPER METHODS (Robust JSON Cleaner) ---

@NonCPS
def extractHashFromResponse(String response) {
    // Cari text di dalam tanda kutip setelah "hash":
    def matcher = response =~ /"hash"\s*:\s*"([^"]+)"/
    if (matcher.find()) {
        return matcher.group(1)
    }
    return ""
}

@NonCPS
def cleanAndParseJson(String rawOutput) {
    // 1. Cari kurung kurawal pembuka '{' pertama
    int firstBrace = rawOutput.indexOf('{')
    // 2. Cari kurung kurawal penutup '}' terakhir
    int lastBrace = rawOutput.lastIndexOf('}')

    if (firstBrace == -1 || lastBrace == -1) {
        throw new Exception("No valid JSON found in output. Raw output start: " + rawOutput.take(100))
    }

    // 3. Potong string hanya ambil dari '{' sampai '}'
    String cleanJsonString = rawOutput.substring(firstBrace, lastBrace + 1)

    // 4. Parse
    def slurper = new JsonSlurperClassic()
    return slurper.parseText(cleanJsonString)
}

@NonCPS
def generateReadableReports(String type, String rawJson) {
    def prettyJson = ""
    def htmlContent = ""
    
    try {
        // --- STEP PENTING: Bersihkan Output Windows sebelum Parse ---
        def jsonObj = cleanAndParseJson(rawJson)
        // ------------------------------------------------------------

        // Buat JSON Rapi
        prettyJson = JsonOutput.prettyPrint(JsonOutput.toJson(jsonObj))
        
        // Data untuk HTML
        def score = jsonObj.security_score ?: 0
        def appName = jsonObj.app_name ?: "Unknown"
        def version = jsonObj.version_name ?: "1.0"
        
        // Warna Score
        def scoreColor = score < 50 ? '#e74c3c' : (score < 75 ? '#f39c12' : '#27ae60')

        // Buat HTML Summary
        htmlContent = """
        <html>
        <head>
            <style>
                body { font-family: sans-serif; padding: 20px; background: #f0f0f0; }
                .card { background: white; padding: 30px; border-radius: 8px; max-width: 600px; margin: auto; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
                h1 { border-bottom: 2px solid #eee; color: #333; }
                .score { font-size: 50px; font-weight: bold; color: ${scoreColor}; text-align: center; margin: 20px 0; }
                table { width: 100%; border-collapse: collapse; margin-top: 20px; }
                td, th { padding: 10px; border-bottom: 1px solid #ddd; text-align: left; }
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
                <p><i>Check <b>${type}_report_pretty.json</b> artifact for full details.</i></p>
            </div>
        </body>
        </html>
        """

    } catch (Exception e) {
        prettyJson = "ERROR PARSING JSON: \n" + e.getMessage() + "\n\n--- RAW OUTPUT ---\n" + rawJson
        htmlContent = "<html><body><h1>Report Generation Failed</h1><p>${e.getMessage()}</p></body></html>"
    }

    return [pretty: prettyJson, html: htmlContent]
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
                    
                    // Note: Tanda @ di depan curl berfungsi agar command tidak di-echo ulang ke output
                    def uploadResponse = bat(script: '@curl -s -F "file=@build/app/outputs/flutter-apk/app-debug.apk" http://localhost:8000/api/v1/upload -H "Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac"', returnStdout: true).trim()
                    String apkHash = extractHashFromResponse(uploadResponse)
                    
                    if (apkHash == "") { error "Upload failed. Raw response: " + uploadResponse }
                    env.APK_HASH = apkHash
                    echo "SAST Hash: ${apkHash}"

                    // Scan
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/scan --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // Get JSON Report
                    def rawJson = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/report_json --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // Generate Readable Report
                    def results = generateReadableReports("sast", rawJson)

                    writeFile file: 'sast_report_pretty.json', text: results.pretty
                    writeFile file: 'sast_summary.html', text: results.html
                    
                    archiveArtifacts artifacts: 'sast_report_pretty.json, sast_summary.html', allowEmptyArchive: false
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
                    def rawJson = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // Generate Readable Report
                    def results = generateReadableReports("dast", rawJson)

                    writeFile file: 'dast_report_pretty.json', text: results.pretty
                    writeFile file: 'dast_summary.html', text: results.html

                    archiveArtifacts artifacts: 'dast_report_pretty.json, dast_summary.html', allowEmptyArchive: false
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