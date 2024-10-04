- if you type a message, then add a file, the message gets wiped
- improvemnts for search modal - when clear search, clear results
- if google drive permission not given,dont show error. toggle permission again or log out
- delete search hist
- when you add multiple files, they get added dupklicated
- breaks when add 3 financial model sheeets (nothing gets pasted)
- show more of user message (expand collapse)
- truncating file message content ... (or handle it like Anthropic. a paste file)

Error Handling: Provide user feedback in case of errors or exceptions. let them submit error report
Test with different search queries.
Test selecting multiple files.
Test including file contents vs. links.
Handle cases where no files are found.
Handle API errors gracefully.

- have a RAG embeddings store on all company docs so that users dont even need to load the files. just use the context given to them
- When refreshing a page and need to auth back in, it takes you back to home instead of the link before you authed.
- Download convo or save message to file
- Chat text box in mobile hidden at first, need to scroll down
- Add vertex, Anthropic
- Add model router for right task and cheapness
- Add artifacts? v0?
- "Bad request" if access /auth/google, add fallback 404 page with link to home or re-route a bad request to home
- Add warning of messages not persisting
- Per user API key to track usage
- EMAIL STUFF
- Persistence or saving in case of refresh
- Add logo
- Add Speech to text and text to speech
- Implement pdf2audio with necessary tweaks
- Add integrations (tools, web, scraping, workflows, lindy, agents, exa, talivy, etc)
- RAG assistants and RAG docs, don't exist? Create prompts on the fly to create new assistant.
- Search for assistant using RAG or whatever
- Add reasoning
- Add ability to write files
- Search specific files
- Add search 1 document and ask questions or get an updated version
- Goth?
- Drive Labels API for what?
- Brand guidelines