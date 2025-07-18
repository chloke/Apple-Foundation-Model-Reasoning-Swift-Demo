import SwiftUI
import FoundationModels

struct ContentView: View {
    @State private var modeSelected = false
    @State private var zeroShot = false
    @State private var zeroShotCoT = false
    @State private var selfCon = false
    @State private var prevTaskComplete = true
    
    @State private var descText = "Please select a mode"
    @State private var instructionsTxt = ""
    @State private var userInput = ""
    @State private var outputText = "Output will appear here."
    
    private let genOptions = GenerationOptions(sampling: .random(top: 5, seed: nil), temperature: 0.2)
    
    struct DropdownMenu: View {
        @State private var selectedLabel = "Select Mode"
        
        @Binding var zeroShot: Bool
        @Binding var zeroShotCoT: Bool
        @Binding var selfCon: Bool
        @Binding var modeSelected: Bool
        @Binding var descText: String

        var body: some View {
            VStack(spacing: 20) {
                Menu {
                    Button("Zero-Shot") {
                        selectedLabel = "Zero-Shot"
                        descText = "This mode will process your prompt without any instructions."
                        modeSelected = true
                        zeroShot = true
                        zeroShotCoT = false
                        selfCon = false
                    }
                    Button("Zero-Shot-CoT") {
                        selectedLabel = "Zero-Shot-CoT"
                        descText = "This mode will process your input as a simple Chain-of-Thought prompt."
                        modeSelected = true
                        zeroShot = false
                        zeroShotCoT = true
                        selfCon = false
                    }
                    Button("Self-Consistency") {
                        selectedLabel = "Self-Consistency"
                        descText = "This mode will first generate three CoT answers to your prompt and choose the most common one for its final answer."
                        modeSelected = true
                        zeroShot = false
                        zeroShotCoT = false
                        selfCon = true
                    }
                } label: {
                    Text(selectedLabel)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                
                Text(descText)
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
            DropdownMenu(zeroShot: $zeroShot, zeroShotCoT: $zeroShotCoT, selfCon: $selfCon, modeSelected: $modeSelected, descText: $descText)

            ScrollView(.vertical) {
                Text(outputText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: 300)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
            .padding()
            
            if modeSelected {
                TextField("Type your question here...", text: $userInput, onCommit: {
                    guard prevTaskComplete else { return }
                    let input = userInput
                    prevTaskComplete = false

                    Task {
                        await runPrompt(input)
                        prevTaskComplete = true
                    }
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            }
        }
        .padding()
    }

    private func runPrompt(_ input: String) async {
        
        if zeroShot {
            instructionsTxt = ""
            outputText = "Loading Zero-Shot..."
        }
        
        if zeroShotCoT || selfCon {
            instructionsTxt = "Let's think step by step."
            if !selfCon {
                outputText = "Loading Zero-Shot-CoT..."
            }
        }
        
        let sessionInstructions = Instructions(instructionsTxt)
        let selfConInstructions = Instructions("You are provided with three solutions to the same problem. Compare every solution to each other and choose the most common solution. Your output should be a unified answer consisting of the two solutions, which are the most similar in their results. Make sure your output contains the result.")
        let selfConResultInstructions = Instructions("You are provided with two similar solutions to the same question. Rephrase them into one unified answer and output only that unified definitive answer/solution. Do not mention your evaluation process or that there were more that one solution. Make sure your output contains the result.")
        
        if zeroShot || zeroShotCoT {
            do {
                try await outputText = generateResponse(helperInput: input, helperInstructions: sessionInstructions)
            } catch {
                outputText = "Error: \(error.localizedDescription)"
            }
        }
        
        if selfCon {
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

                //now compare the results:
                outputText = "Loading evaluation..."
                let evaluationOutput = try await generateResponse(
                    helperInput: "SOLUTION 1: \(outputONE) SOLUTION 2: \(outputTWO) SOLUTION 3: \(outputTHREE)",
                    helperInstructions: selfConInstructions
                )
                
                //final result output:
                outputText = "Loading result..."
                outputText = try await generateResponse(
                    helperInput: evaluationOutput,
                    helperInstructions: selfConResultInstructions
                )
                
            } catch {
                outputText = "Error: \(error.localizedDescription)"
            }
        }
    }
}
