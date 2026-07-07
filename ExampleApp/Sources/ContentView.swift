// This file is licensed to you under the Apache License, Version 2.0 
// (http://www.apache.org/licenses/LICENSE-2.0) or the MIT license 
// (http://opensource.org/licenses/MIT), at your option.
//
// Unless required by applicable law or agreed to in writing, this software is 
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF 
// ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE 
// files for the specific language governing permissions and limitations under
// each license.

import SwiftUI

struct ContentView: View {
    @State private var showingCamera = true  // Start with camera open
    @State private var showingSettings = false
    @State private var showingVerify = false
    @State private var capturedImage: UIImage?
    @State private var showingSuccess = false
    @State private var successMessage = ""
    @State private var c2paManager = C2PAManager.shared

    var body: some View {
        ZStack {
            // Always show camera view as the main interface
            CameraViewWrapper(
                showingCamera: $showingCamera,
                showingSettings: $showingSettings,
                showingVerify: $showingVerify,
                capturedImage: $capturedImage,
                showingSuccess: $showingSuccess,
                successMessage: $successMessage
            )
            .edgesIgnoringSafeArea(.all)

            if c2paManager.isProcessing {
                Color.black.opacity(0.5)
                    .edgesIgnoringSafeArea(.all)

                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)

                    Text("Signing image...")
                        .foregroundColor(.white)
                        .padding(.top)
                }
            }

            // Success overlay that auto-dismisses
            if showingSuccess {
                Color.black.opacity(0.5)
                    .edgesIgnoringSafeArea(.all)

                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)

                    Text(successMessage)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .onAppear {
                    // Auto-dismiss after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showingSuccess = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(isPresented: $showingSettings)
        }
        .sheet(isPresented: $showingVerify) {
            VerifyWebView(isPresented: $showingVerify)
        }
    }
}

struct CameraViewWrapper: View {
    @Binding var showingCamera: Bool
    @Binding var showingSettings: Bool
    @Binding var showingVerify: Bool
    @Binding var capturedImage: UIImage?
    @Binding var showingSuccess: Bool
    @Binding var successMessage: String
    @State private var c2paManager = C2PAManager.shared

    var body: some View {
        ZStack {
            CustomCameraView(capturedImage: $capturedImage) { image, location in
                c2paManager.signAndSaveImage(image, location: location) { success, _, _ in
                    showingCamera = false
                    if success {
                        successMessage = "Credentials Added!"
                        showingSuccess = true
                    }
                }
            }

            VStack {
                HStack {
                    Button(
                        action: {
                            showingSettings = true
                        },
                        label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                    )
                    .padding(.leading)

                    Spacer()

                    Button(
                        action: {
                            showingVerify = true
                        },
                        label: {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.title2)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                    )
                    .padding(.trailing)
                }
                .padding(.top, 50)

                Spacer()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(isPresented: $showingSettings)
        }
        .sheet(isPresented: $showingVerify) {
            VerifyWebView(isPresented: $showingVerify)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
