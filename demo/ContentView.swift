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
    
    @State private var session: LanguageModelSession? = nil
    
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
            
            TextField("Type your question here...", text: $userInput, onCommit: {
                guard modeSelected else { return }
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
        
        let SessionInstructions = Instructions(instructionsTxt)
        let SelfConInstructions = Instructions("You are provided with three solutions to the same problem. Compare every solution to each other and choose the most common solution. Your output should be a unified answer consisting of the two solutions, which are the most similar in their results.")
        let SelfConResultInstructions = Instructions("You are provided with two similar solutions to the same question. Rephrase them into one unified answer and output only that unified definitive answer/solution. Do not mention your evaluation process or that there were more that one solution.")
        
        if zeroShot || zeroShotCoT {
            let firstSession = LanguageModelSession(instructions: SessionInstructions)
            firstSession.prewarm()
            
            do {
                let firstPrompt = Prompt(input)
                let firstResponse = try await firstSession.respond(to: firstPrompt, options: genOptions)
                let firstOutput = firstResponse.content
                
                await MainActor.run {
                    outputText = firstOutput
                }
            } catch {
                await MainActor.run {
                    outputText = "Error: \(error.localizedDescription)"
                }
            }
        }
        
        if selfCon {
            outputText = "Loading first CoT...(1/5)"
            let firstSession = LanguageModelSession(instructions: SessionInstructions)
            firstSession.prewarm()
            
            do {
                let firstPrompt = Prompt(input)
                let firstResponse = try await firstSession.respond(to: firstPrompt, options: genOptions)
                let firstOutput = firstResponse.content
                print("1ST OUTPUT: \(firstOutput)")
                
                //2nd
                outputText = "Loading second CoT...(2/5)"
                let secondSession = LanguageModelSession(instructions: SessionInstructions)
                secondSession.prewarm()
                let secondPrompt = Prompt(input)
                let secondResponse = try await secondSession.respond(to: secondPrompt, options: genOptions)
                let secondOutput = secondResponse.content
                print("2ND OUTPUT: \(secondOutput)")
                
                //3rd
                outputText = "Loading third CoT...(3/5)"
                let thirdSession = LanguageModelSession(instructions: SessionInstructions)
                thirdSession.prewarm()
                let thirdPrompt = Prompt(input)
                let thirdResponse = try await thirdSession.respond(to: thirdPrompt, options: genOptions)
                let thirdOutput = thirdResponse.content
                print("3RD OUTPUT: \(thirdOutput)")
                
                //Evaluation
                outputText = "Loading Evaluation...(4/5)"
                let finalSession = LanguageModelSession(instructions: SelfConInstructions)
                finalSession.prewarm()
                let finalPrompt = Prompt("SOLUTION 1: \(firstOutput) SOLUTION 2: \(secondOutput) SOLUTION 3: \(thirdOutput)")
                let finalResponse = try await finalSession.respond(to: finalPrompt, options: genOptions)
                let finalOutput = finalResponse.content
                print("EVALUATION PROCESS: \(finalOutput)")
                
                //Evaluation Result
                outputText = "Loading final answer...(5/5)"
                let resultSession = LanguageModelSession(instructions: SelfConResultInstructions)
                resultSession.prewarm()
                let resultPrompt = Prompt(finalOutput)
                let resultResponse = try await resultSession.respond(to: resultPrompt, options: genOptions)
                let resultOutput = resultResponse.content
                
                
                await MainActor.run {
                    outputText = resultOutput
                }
            } catch {
                await MainActor.run {
                    outputText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
