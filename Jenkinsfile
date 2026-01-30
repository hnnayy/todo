import groovy.json.JsonSlurperClassic 
import groovy.json.JsonOutput

// --- HELPER METHODS ---

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
    int firstBrace = rawOutput.indexOf('{')
    int lastBrace = rawOutput.lastIndexOf('}')
    if (firstBrace == -1 || lastBrace == -1) { return null }
    return rawOutput.substring(firstBrace, lastBrace + 1)
}

// -----------------------------------------------------------------------

pipeline {
    agent any

    parameters {
        choice(name: 'BUILD_TYPE', choices: ['release', 'debug'], description: 'Pilih Tipe Build')
    }

    environment {
        ANDROID_HOME = "C:\\Users\\SECULAB\\AppData\\Local\\Android\\Sdk"
        PATH = "${env.ANDROID_HOME}\\tools;${env.ANDROID_HOME}\\platform-tools;${env.PATH}"
        AVD_NAME = "Pixel_4_XL_2"
        APP_PACKAGE = "com.example.mobileapp" 
        APK_OUTPUT_DIR = "C:\\ApksGenerated"
        MOBSF_API_KEY = "fe55f4207016d5c6515a1df3b80a710d5d3b40d679462b27e333b004598d75ac"
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/hnnayy/todo.git', credentialsId: 'github-pat-global-test'
            }
        }

        stage('Prepare Folders') {
            steps {
                bat 'if not exist apk-outputs mkdir apk-outputs'
                bat "if not exist \"${env.APK_OUTPUT_DIR}\" mkdir \"${env.APK_OUTPUT_DIR}\""
            }
        }

        stage('Clean Folder') {
            steps {
                bat "del /Q \"${env.APK_OUTPUT_DIR}\\*\""
            }
        }

        stage('Build Application') {
            steps {
                bat 'git config --global --add safe.directory C:/flutter'
                bat 'flutter pub get'
                bat "flutter build apk --${params.BUILD_TYPE}"
            }
        }

        stage('SAST Mobile') {
            steps {
                script {
                    def apkSourcePath = "build/app/outputs/flutter-apk/app-${params.BUILD_TYPE}.apk"
                    [cite_start]// Upload ke MobSF [cite: 75, 77]
                    def uploadResponse = bat(script: "@curl -s -F \"file=@${apkSourcePath}\" http://localhost:8000/api/v1/upload -H \"Authorization: ${env.MOBSF_API_KEY}\"", returnStdout: true).trim()
                    env.APK_HASH = extractHashFromResponse(uploadResponse)
                    
                    if (env.APK_HASH == "") { error "Upload failed." }
                    
                    [cite_start]// Scan [cite: 98, 100]
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/scan --data \"hash=${env.APK_HASH}\" -H \"Authorization: ${env.MOBSF_API_KEY}\"", returnStdout: true)
                }
            }
        }

        stage('Setup Emulator') {
            steps {
                script {
                    def devices = bat(script: "adb devices", returnStdout: true)
                    if (!devices.contains("emulator")) {
                        bat "start /b \"\" \"${env.ANDROID_HOME}\\emulator\\emulator.exe\" -avd \"${env.AVD_NAME}\" -no-window -no-audio -gpu swiftshader_indirect -wipe-data"
                        sleep(60)
                        bat "adb wait-for-device"
                    }
                }
            }
        }

        stage('Install APK') {
            steps {
                script {
                    def sourcePath = "build\\app\\outputs\\flutter-apk\\app-${params.BUILD_TYPE}.apk"
                    bat "adb install -r \"${sourcePath}\""
                }
            }
        }

        stage('DAST Mobile') {
            steps {
                script {
                    echo 'Running DAST...'
                    bat "adb shell input keyevent 82" // Unlock
                    
                    [cite_start]// Start Analysis [cite: 513]
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/start_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: ${env.MOBSF_API_KEY}\"", returnStdout: true)
                    sleep(25) 

                    [cite_start]// Frida Instrumentation [cite: 724]
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/frida/instrument --data \"hash=${env.APK_HASH}&default_hooks=api_monitor,ssl_pinning_bypass,root_bypass,debugger_check_bypass&auxiliary_hooks=&frida_code=\" -H \"Authorization: ${env.MOBSF_API_KEY}\"", returnStdout: true)
                    sleep(5)

                    // Hybrid Interaction & Monkey (Ultra Fast)
                    try {
                        bat "adb shell monkey -p ${env.APP_PACKAGE} --throttle 200 -v 50"
                    } catch (e) { echo "Monkey done" }

                    [cite_start]// Stop Analysis [cite: 866]
                    bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/stop_analysis --data \"hash=${env.APK_HASH}\" -H \"Authorization: ${env.MOBSF_API_KEY}\"", returnStdout: true)

                    [cite_start]// Get Dynamic JSON Report [cite: 891]
                    def rawDastOutput = bat(script: "@curl -s -X POST --url http://localhost:8000/api/v1/dynamic/report_json --data \"hash=${env.APK_HASH}\" -H \"Authorization: ${env.MOBSF_API_KEY}\"", returnStdout: true).trim()
                    def cleanDastJson = cleanJsonString(rawDastOutput)

                    if (cleanDastJson) {
                        writeFile file: 'dast_report_full.json', text: cleanDastJson
                        
                        // --- EXTRACTION LOGIC FOR SPECIFIC DATA ---
                        def jsonSlurper = new JsonSlurperClassic()
                        def report = jsonSlurper.parseText(cleanDastJson)

                        // 1. XML Files - Mengambil data file XML dari laporan dinamis
                        def xmlFiles = report.xml_files ?: []
                        writeFile file: 'extracted_xml_list.txt', text: xmlFiles.join('\n')

                        // 2. SQLite Database - Mengambil daftar database SQLite yang terdeteksi
                        def sqliteFiles = report.sqlite_db ?: []
                        writeFile file: 'extracted_sqlite_list.txt', text: sqliteFiles.join('\n')

                        // 3. Base64 Decoded Strings - Mengambil string Base64 yang berhasil didekode
                        def base64Data = report.decoded_base64 ?: []
                        writeFile file: 'extracted_base64_decoded.json', text: JsonOutput.toJson(base64Data)

                        // 4. Trackers - Mengambil data trackers yang terdeteksi dalam aplikasi
                        def trackers = report.trackers ?: [:]
                        writeFile file: 'extracted_trackers.json', text: JsonOutput.toJson(trackers)

                        echo "✅ Specific data (XML, SQLite, Base64, Trackers) extracted."
                    }
                }
            }
        }

        stage('Cleanup') {
            steps {
                bat 'taskkill /F /IM qemu-system-x86_64.exe /T || echo Already stopped'
            }
        }
    }

    post {
        always {
            // Melampirkan semua hasil ekstraksi ke Jenkins Artifacts
            archiveArtifacts artifacts: '*.json, *.txt', allowEmptyArchive: true
            
            emailext (
                subject: "Security Report: ${env.JOB_NAME} - #${env.BUILD_NUMBER}",
                body: "Build finished. XML, SQLite, Base64, and Tracker reports are attached.",
                to: "mutiahanin2017@gmail.com, gghurl111@gmail.com",
                attachmentsPattern: "extracted_*.json, extracted_*.txt, dast_report_full.json"
            )
        }
    }
}