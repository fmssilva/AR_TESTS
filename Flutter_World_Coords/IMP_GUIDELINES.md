								
	0 — Before Anything Else							
		keep in mind the phase and project guides:						
								
			"C:\Users\franc\Desktop\AR\Flutter_World_Coords\AR_WALL_IMPLEMENTATION_PLAN.md		"					
		Read all project guide files and confirm they are all up to date. read all the lines of th files:						
								
								
								
								
								
		Read all relevant existing files in scope — understand structure, types, hooks, state, providers, and components before touching anything						
		Create a  compreensive TODO list of all tasks before starting. Do not skip steps.						
								
	1 — Think Before You Code							
		For every single issue or feature, you must stop and evaluate at two separate layers before touching the IDE:						
			Architecture level: Where does this asset live? Formulate 3 distinct structural options, explain the trade-offs directly in the chat, and choose the absolute cleanest.					
			Implementation level: How do we write this locally? Formulate 3 distinct coding paths, present them in the chat, and choose the most robust.					
		The Benchmark Standard: Code this app as if it were an academic reference implementation. If central types, hooks, or providers are messy, do not work around them with adapters or backward-compatibility wrappers. Propose the structural change, break down the 3 best options, get confirmation, and rewrite it cleanly.						
								
	2 — Code Quality Rules							
		2.1 Separation of Concerns & Clean Code						
			Zero Duplication: Search the workspace for existing types, abstractions, custom hooks, or utility extensions before writing a new helper.					
			Single Responsibility Principle (SRP): One file, one job. Never use a single file to group multiple business logic providers, and never create a generic utils.dart file as a dumping ground. If a subdomain model or utility expands, split it down cleanly by sub-domain.					
			Domain-Centric Structure: Group files by feature/subdomain. Keep widgets, presentation cubits/providers, models, and platform logic nested within their specific feature directories. Do not scatter presentation pieces across generic layer folders.					
			Self-Documenting Code Base: Name directories, files, interfaces, and methods so descriptive that a student can read the file tree and immediately understand the data lifecycle without deep documentation.					
			No Speculative Engineering: Implement only the exact features required by the current scope. Do not write "might be useful tomorrow" parameters, endpoints, or variations.					
			Lean Execution over Custom Re-invention: Use robust, trusted industry standard libraries instead of building custom math or state ecosystems by hand. Keep the code concise, line-counts minimal, and execution paths direct.					
		2.2 Academic Annotation & Logging Standards						
			Infinitive Function Summaries: Place a short, direct comment above each function using the infinitive form (e.g., // Initialize native platform session views, // Compute global drift error matrix).					
			Dev-to-Dev Inline Commentary: Use concise inline bullet-point comments to explain highly technical matrix transforms, coordinate shifts, or event loops. Write them like two experienced developers discussing code at a whiteboard.					
			Zero Emojis & Strict ASCII: Do not include emojis or non-ASCII characters anywhere in code, comments, or terminal outputs. Use clear equivalents:					
				Replace ✓ with [ok]				
				Replace → with ->				
				Replace » with >>				
			Assert-Driven Validation: Replace simple print logging with explicit programmatic assertions (assert(...)) at key invariant boundaries. If a diagnostic states a tracking matrix is aligned, make sure a mathematical assertion enforces that state.					
								
	3 — UI/UX Rules							
		2.1 Branding and Design Execution						
			Strictly enforce the application typography, contrast constraints, and spatial padding grids mapped in					
				PROJECT_GUIDES/DESIGN.				
			Ensure perfect contrast and accessibility across both light and dark display modes.					
			Abstract all user-facing strings through an internationalization (i18n) localized engine. Never hardcode raw strings in production widgets.					
		2.2 Visual Philosophy						
			Single Focal Point: Every viewport layout must contain a distinct visual hierarchy. The user's eye must instantly recognize the primary point of action.					
			Considered vs. Decorated Design: Every line, margin, and layout block must serve a distinct utility or information purpose. Eliminate unnecessary decorations.					
			Anti-Template Aesthetic: Avoid predictable card grids, default hero-plus-button patterns, and generic mobile application templates. The screen layout must be balanced, bespoke, and professional.					
								
								
	4 — After Implementing							
		Testing is treated as a horizontal progression layer. You must complete, fix, and pass 100% of the active layer's assertions before moving code or logic down to the next tier.						
		[Layer 1: Unit] -> [Layer 2: Widget] -> [Layer 3: Integration] -> [Layer 4: Browser] -> [Layer 5: Device]						
								
					t			
								
								
								
					5 — Testing			
						Rules that apply to ALL layers:		
							Do not skip layers. Do not move to the next layer until the current one is 100% green.	
							Add all test steps to the TODO list upfront — including the iterate-until-green loop for each layer.	
							When fixing failures: understand the big picture first. Ask — is the test wrong, or is the logic wrong? Think 3 options, choose best, re-run. Repeat until 100%.	
							After each layer completes, give a short summary of what was tested so i have a clear picture of the main logic you used	
								
						### LAYER 1 — UNIT TESTS		
						Implement tests to confirm business logic, state management, utilities, etc are all correct		
						Location: .../domains/DOMAIN/test/unit/		
						"For these tests, use ProviderContainer to test providers in isolation - No widgets, no MaterialApp, no routing; 
Command: flutter test lib/domains/DOMAIN/test/unit/ --reporter=compact"		
						Make thesse tests real as possible. Load real data... Don't mock our own code.		
						"Acceptance criteria:
- All business logic paths covered, state transitions, functions... 
- Edge cases tested (empty, null, max values)"		
								
						### LAYER 2 — WIDGET TESTS		
						tests that actually mount real widgets/components and trigger lifecycles, test user interactions (tap, scroll, drag, text input); Navigation flows (routing with real routes); Provider integration with UI (does tapping update state?); Lifecycle issues (provider updates during build, etc.); UI state (buttons enabled/disabled, text changes, widgets/components visible), test real flow of events in the widgets/components tree, interaction with providers, syncrnous problems, auth problems, etc. 		
						Location: .../domains/DOMAIN/test/widgets/		
						"""to test » Mount real widgets with UncontrolledProviderScope; Use real GoRouter configuration (can stub page contents); - Simulate user actions with WidgetTester:
  * tester.tap(find.text('Button'))
  * tester.enterText(find.byType(TextField), 'text')
  * tester.drag(find.byType(ListView), Offset(0, -500))
  * tester.scrollUntilVisible(find.text('Item'), 500)
- Assert on:
  * Widget visibility: expect(find.text('X'), findsOneWidget)
  * Provider state: expect(container.read(provider), expectedValue)
  * Navigation: expect(GoRouter.of(context).location, '/expected')""
Command: flutter test lib/domains/DOMAIN/test/widgets/ --reporter=compact"		
						"Acceptance criteria:
- Critical user paths covered (navigation, form submission, etc.)
- Lifecycle errors caught (provider updates during build)
- Tests use REAL widgets/components, REAL providers, REAL routes
- Only override providers that need hardware (camera, AR, GPS) — replace those with Mock implementations"		
								
						### LAYER 3 — INTEGRATION TESTS (PC, no device)		
						Tests with the full app mounted to confirm the most important flows user journeys end-to-end, state management along the journey, error paths (network failures, invalid data)		
						"Write 3 types:
1. Smoke tests — confirm all main components render without errors; add concise logs like ""ComponentX rendered correctly""
2. User journey tests — cover the 2–5 main flows for this feature (navigate → interact → assert)
3. Error path tests — what happens if the repository throws? If data is empty? If network fails?


"		
						"Location: .../domains/DOMAIN/test/integration
"		
						"How to test:
- Same as widget tests but with full app mounted
- Use `integration_test` package to run on real browser
- Mock external APIs (use fake HTTP responses)
Command: flutter test lib/domains/DOMAIN/test/integration/ --reporter=compact"		
						"Acceptance criteria:
- tests covering most critical user journeys
- Error paths tested (what if API fails?)
- Tests are deterministic (use mocked HTTP, not real API
- Full app mounted (MaterialApp.router + GoRouter + all real providers)
- Mock only hardware providers (camera, AR session, GPS)"		
								
						### RUN ALL 3 LAYERS TOGETHER:		
							to confirm all tests in all features are still ok.	
							run: flutter test lib/ --reporter=compact	
							» lets make sure that you atually have tests to confirm that all widgets are correctly displayed and in the correct position with the corret dimensions and style... and this for all widgets along the flow of possible actions user cand do with this phase implementation funtionalities. don't want to find any error in manual test later, that could be found in automated integration tests now.	
								
								
								
								
								
								
								
								
								
								
								
								
								
								
								
								
								
						### LAYER 4 — Browser Integration Tests		
						What: same tests as Layer 3 but running inside the real browser		
						Location: integration_test/FEATURE_NAME_test.dart		
						Uses: package:integration_test/integration_test.dart		
						Catches: Chrome rendering bugs (Impeller, Vulkan), real asset loading, real platform channels, screen density issues, spacing, overflows, errors and exceptions... 		
						"Run these tests on the chrome browser:
    Start-Process chromedriver -ArgumentList ""--port=4444"" -WindowStyle Hidden
    flutter drive --driver=test_driver/integration_test.dart --target=integration_test/xxx_test.dart -d chrome > __out.txt 2>&1"		
						When fixing failures: understand the big picture first. Ask — is the test wrong, or is the logic wrong? Think 3 options, choose best, re-run. Repeat until 100%.		
								
								
						### LAYER 5 — Phone Integration Tests		
						What: run the same tests as layer 4 but now running inside the real phone device		
						For that, i already connected my phone in dev mode and connected to my PC through wireless and adb already is able to find it. So just find the phone and do a smoke test to confirm it is connected (try at least 3 times before giving up) 		
						Location: integration_test/FEATURE_NAME_test.dart		
						Uses: package:integration_test/integration_test.dart		
						Catches: Android rendering bugs (Impeller, Vulkan), real asset loading, real platform channels, screen density issues, spacing, overflows, errors and exceptions... 		
						run the app directly in my phone using adb to connct to it and then get the logs in the file __out.txt		
						When fixing failures: understand the big picture first. Ask — is the test wrong, or is the logic wrong? Think 3 options, choose best, re-run. Repeat until 100%.		
								
						» at the end of this layer 5 tests, do a deep analysis and confirm if the test are well automated and they run smooth as is, using my device directly, 		
						or if it would be better to use tools like Patrol or Maestro for device testing... would they bring any value or the test infrastructure we have is already good and well automated? 		
								
								
								
								
								
								
								
								
								
								
								
								
								
								
								
								
								
								
								
								
								
								
								
					You have unlimited time. Be thorough, not fast. Only stop when every layer is ✓			
								
								
	6 — Code writing							
		Do not create files in your memory and then dump them, because you will run out of memory.						
		Instead create the file first and add there the text directly so if you get interrupted we don't lose all the work						
								
	7 — Terminal							
		PowerShell → use ; not &&						
		"Don't apply pipes or filters directly to terminal (ex 2>&1 | findstr /C:""..."" )
Send the logs to a file __out.txt and then you check the logs there in the file (> __out.txt  2>&1)"						
								
	8 — On Finishing							
		Update the phase guide document to mark the things that were done and some update of some change we did because when implementing things we found out those changes were needed or better						
								
			"C:\Users\franc\Desktop\AR\Flutter_World_Coords\AR_WALL_IMPLEMENTATION_PLAN.md		"					
		And then give a short chat summary: what was implemented, in which file/folder, and what the data flow is. No summary files.						
								
	So create a Compreensive TODO list of tasks to do so you don't skip any step							
	Take your time. You have unlimited time and tokens. So I want quality over speed. Be good, not fast. 							