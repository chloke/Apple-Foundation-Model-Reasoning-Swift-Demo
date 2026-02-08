import SwiftUI
import FoundationModels

struct ContentView: View {
    enum Mode {
        case none
        case zeroShot
        case zeroShotCoT
        case selfConsistency

        var label: String {
            switch self {
            case .none:
                return "Select Mode"
            case .zeroShot:
                return "Zero-Shot"
            case .zeroShotCoT:
                return "Zero-Shot-CoT"
            case .selfConsistency:
                return "Self-Consistency"
            }
        }

        var description: String {
            switch self {
            case .none:
                return "Please select a mode"
            case .zeroShot:
                return "This mode will process your prompt without any instructions."
            case .zeroShotCoT:
                return "This mode will process your input as a simple Chain-of-Thought prompt."
            case .selfConsistency:
                return "This mode will first generate three CoT answers to your prompt and choose the most common one for its final answer."
            }
        }
    }

    @State private var selectedMode: Mode = .none
    @State private var prevTaskComplete = true
    
    @State private var instructionsTxt = ""
    @State private var userInput = ""
    @State private var outputText = "Output will appear here."
    @State private var currentTask: Task<Void, Never>?
    @State private var isPulsing = false
    
    private var model = SystemLanguageModel.default
    
    private let genOptions = GenerationOptions(sampling: .random(top: 5, seed: nil), temperature: 0.2)
    
    struct DropdownMenu: View {
        @Binding var selectedMode: Mode

        var body: some View {
            VStack(spacing: 20) {
                Menu {
                    Button("Zero-Shot") {
                        selectedMode = .zeroShot
                    }
                    Button("Zero-Shot-CoT") {
                        selectedMode = .zeroShotCoT
                    }
                    Button("Self-Consistency") {
                        selectedMode = .selfConsistency
                    }
                } label: {
                    Text(selectedMode.label)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                
                Text(selectedMode.description)
            }
            .padding()
        }
    }
    
    func generateResponse(helperInput: String, helperInstructions: Instructions) async throws -> String {
        let session = LanguageModelSession(instructions: helperInstructions)
        session.prewarm()
        let prompt = Prompt(helperInput)
        let response = try await session.respond(to: prompt, options: genOptions)
        let output = response.content
        return output
    }
    
    var body: some View {
        VStack(spacing: 10) {
            DropdownMenu(selectedMode: $selectedMode)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    if !prevTaskComplete {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.gray.opacity(0.7))
                                .frame(width: 8, height: 8)
                                .scaleEffect(isPulsing ? 1.0 : 0.6)
                                .opacity(isPulsing ? 1.0 : 0.4)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                                .onAppear { isPulsing = true }
                                .onDisappear { isPulsing = false }
                            Text("Running...")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(outputText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: 300)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
            .padding()
            
            if selectedMode != .none {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Type your question here...", text: $userInput, onCommit: {
                        guard prevTaskComplete else { return }
                        guard checkForAppleIntelligence() else { return }
                        let input = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !input.isEmpty else {
                            outputText = "Please enter a question."
                            return
                        }
                        prevTaskComplete = false
                        currentTask = Task {
                            await runPrompt(input)
                            prevTaskComplete = true
                            currentTask = nil
                        }
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(!prevTaskComplete)

                    if !prevTaskComplete {
                        HStack(spacing: 12) {
                            Text("Running...")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Button("Cancel") {
                                currentTask?.cancel()
                                currentTask = nil
                                prevTaskComplete = true
                                outputText = "Canceled."
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .padding()
    }
    
    private func checkForAppleIntelligence() -> Bool {
        switch model.availability {
            case .available:
                return true
            case .unavailable(.deviceNotEligible):
                outputText = "Error: Device not eligible for Apple Intelligence."
                return false
            case .unavailable(.appleIntelligenceNotEnabled):
                outputText = "Error: Apple Intelligence not enabled, please turn on in settings."
                return false
            case .unavailable(.modelNotReady):
                outputText = "Error: The model isn't ready because it's still downloading or because of other system reasons."
                return false
            case .unavailable(let other):
                outputText = "Error: The model is unavailable for an unknown reason."
                return false
        }
    }

    private func runPrompt(_ input: String) async {
        if Task.isCancelled { return }
        
        if selectedMode == .zeroShot {
            instructionsTxt = ""
            outputText = "Loading Zero-Shot..."
        }
        
        if selectedMode == .zeroShotCoT || selectedMode == .selfConsistency {
            instructionsTxt = "Let's think step by step."
            if selectedMode != .selfConsistency {
                outputText = "Loading Zero-Shot-CoT..."
            }
        }
        
        let sessionInstructions = Instructions(instructionsTxt)
        let selfConInstructions = Instructions("You are provided with three solutions to the same problem. Compare every solution to each other and choose the most common solution. Your output should be a unified answer consisting of the two solutions, which are the most similar in their results. Make sure your output contains the result.")
        let selfConResultInstructions = Instructions("You are provided with two similar solutions to the same question. Rephrase them into one unified answer and output only that unified definitive answer/solution. Do not mention your evaluation process or that there were more that one solution. Make sure your output contains the result.")
        
        if selectedMode == .zeroShot || selectedMode == .zeroShotCoT {
            do {
                let result = try await generateResponse(helperInput: input, helperInstructions: sessionInstructions)
                if Task.isCancelled { return }
                outputText = result
            } catch {
                outputText = "Error: \(error.localizedDescription)"
            }
        }
        
        if selectedMode == .selfConsistency {
            do {
                //run the initial CoT prompt three times in parallel:
                outputText = "Loading initial answers (this might take some time)..."
                async let one = generateResponse(helperInput: input, helperInstructions: sessionInstructions)
                async let two = generateResponse(helperInput: input, helperInstructions: sessionInstructions)
                async let three = generateResponse(helperInput: input, helperInstructions: sessionInstructions)

                //wait for all three to finish:
                let outputONE = try await one
                let outputTWO = try await two
                let outputTHREE = try await three
                if Task.isCancelled { return }

                //now compare the results:
                outputText = "Loading evaluation..."
                let evaluationOutput = try await generateResponse(
                    helperInput: "SOLUTION 1: \(outputONE) SOLUTION 2: \(outputTWO) SOLUTION 3: \(outputTHREE)",
                    helperInstructions: selfConInstructions
                )
                if Task.isCancelled { return }
                
                //final result output:
                outputText = "Loading result..."
                let finalOutput = try await generateResponse(
                    helperInput: evaluationOutput,
                    helperInstructions: selfConResultInstructions
                )
                if Task.isCancelled { return }
                outputText = finalOutput
                
            } catch {
                outputText = "Error: \(error.localizedDescription)"
            }
        }
    }
}
