import groovy.json.JsonSlurperClassic 
import groovy.json.JsonOutput 

// --- HELPER METHODS (Ditaruh di luar pipeline) ---

@NonCPS
def extractHashFromResponse(String response) {
    def matcher = response =~ /"hash"\s*:\s*"([^"]+)"/
    if (matcher.find()) {
        return matcher.group(1)
    }
    return ""
}

@NonCPS
def generateReadableReports(String type, String rawJson) {
    // Default values jika error
    def prettyJson = "Error parsing JSON. Raw content: \n" + rawJson
    def htmlContent = "<html><body><h1>Error generating report</h1><p>Please check Jenkins logs and Script Approval.</p></body></html>"
    
    try {
        // 1. Parse Raw JSON
        def slurper = new JsonSlurperClassic()
        def jsonObj = slurper.parseText(rawJson)

        // 2. Buat JSON PRETTY PRINT
        prettyJson = JsonOutput.prettyPrint(JsonOutput.toJson(jsonObj))
        
        // 3. Buat HTML SUMMARY
        def score = jsonObj.security_score ?: 0
        def appName = jsonObj.app_name ?: "Unknown"
        def version = jsonObj.version_name ?: "1.0"
        
        // Tentukan warna berdasarkan score
        def scoreColor = score < 50 ? '#e74c3c' : (score < 75 ? '#f39c12' : '#27ae60')

        htmlContent = """
        <html>
        <head>
            <style>
                body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f4f4f4; padding: 20px; }
                .container { background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 0 10px rgba(0,0,0,0.1); max-width: 800px; margin: auto; }
                h1 { color: #2c3e50; border-bottom: 2px solid #eee; padding-bottom: 10px; }
                .score-box { font-size: 48px; font-weight: bold; color: ${scoreColor}; }
                .info-table { width: 100%; margin-top: 20px; border-collapse: collapse; }
                .info-table th, .info-table td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
                .badge { padding: 5px 10px; border-radius: 4px; color: white; font-weight: bold; }
                .type-badge { background-color: #3498db; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>${type.toUpperCase()} Security Report</h1>
                <p>Target App: <b>${appName}</b> (v${version})</p>
                
                <div style="text-align: center; margin: 30px 0;">
                    <div>Security Score</div>
                    <div class="score-box">${score}/100</div>
                </div>

                <table class="info-table">
                    <tr>
                        <th>Scan Type</th>
                        <td><span class="badge type-badge">${type.toUpperCase()}</span></td>
                    </tr>
                    <tr>
                        <th>Analysis Status</th>
                        <td>Completed Successfully</td>
                    </tr>
                </table>

                <br>
                <h3>Technical Details:</h3>
                <p>Please download the attached <b>${type}_report_pretty.json</b> artifact to see the full details.</p>
            </div>
        </body>
        </html>
        """
    } catch (Exception e) {
        // Jika terjadi error (misal Script Approval belum di-approve), 
        // kita tangkap errornya supaya Pipeline TIDAK CRASH.
        prettyJson = "ERROR: Could not parse JSON. Ensure 'In-process Script Approval' is configured in Jenkins.\nException: " + e.getMessage()
    }

    // Kembalikan Map. Karena ada try-catch, variabel ini pasti terisi (entah sukses atau error)
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
        // Checkout code
        stage('Checkout') {
            steps {
                echo 'Starting Checkout stage'
                git branch: 'main',
                    url: 'https://github.com/hnnayy/todo.git',
                    credentialsId: 'github-pat-global-test'
            }
        }

        // Prepare folders
        stage('Prepare Folders') {
            steps {
                bat 'if not exist apk-outputs mkdir apk-outputs'
                bat "if not exist \"${env.APK_OUTPUT_DIR}\" mkdir \"${env.APK_OUTPUT_DIR}\""
                bat "del /Q \"${env.APK_OUTPUT_DIR}\\*\"" 
            }
        }

        // Build Debug APK
        stage('Build Application') {
            steps {
                echo 'Starting Build Application stage'
                bat 'git config --global --add safe.directory C:/flutter'
                bat 'flutter pub get'
                bat 'flutter build apk --debug'
            }
        }

        // SAST Mobile (JSON READABLE)
        stage('SAST Mobile') {
            steps {
                script {
                    echo 'Running SAST...'
                    
                    // 1. Upload
                    def uploadResponse = bat(script: 'curl -s -F "file=@build/app/outputs/flutter-apk/app-debug.apk" http://localhost:8000/api/v1/upload -H "Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac"', returnStdout: true).trim()
                    String apkHash = extractHashFromResponse(uploadResponse)
                    
                    if (apkHash == "") { error "Upload failed. No hash returned." }
                    env.APK_HASH = apkHash
                    echo "SAST Hash: ${apkHash}"

                    // 2. Scan
                    bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/scan --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // 3. Get JSON Report
                    def rawJson = bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/report_json --data \"hash=${apkHash}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // 4. GENERATE READABLE REPORT
                    // Panggil helper method. Jika permission error, dia tidak akan crash pipeline, tapi return error text.
                    def results = generateReadableReports("sast", rawJson)

                    writeFile file: 'sast_report_pretty.json', text: results.pretty
                    writeFile file: 'sast_summary.html', text: results.html

                    echo "SAST Reports generated."
                    
                    archiveArtifacts artifacts: 'sast_report_pretty.json, sast_summary.html', allowEmptyArchive: false
                }
            }
        }

        // Setup Emulator & Install
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

        // DAST Mobile (JSON READABLE)
        stage('DAST Mobile') {
            steps {
                script {
                    echo 'Running DAST...'
                    
                    // Start
                    bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/dynamic/start_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()
                    
                    sleep(time: 40, unit: 'SECONDS') 

                    // Stop
                    bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/dynamic/stop_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // Get JSON Report
                    def rawJson = bat(script: "curl -s -X POST --url http://localhost:8000/api/v1/dynamic/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac\"", returnStdout: true).trim()

                    // Generate Readable Report
                    def results = generateReadableReports("dast", rawJson)

                    writeFile file: 'dast_report_pretty.json', text: results.pretty
                    writeFile file: 'dast_summary.html', text: results.html

                    echo "DAST Reports generated."

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
            echo 'Pipeline finished.'
            archiveArtifacts artifacts: 'apk-outputs/*.apk', allowEmptyArchive: true
        }
    }
}