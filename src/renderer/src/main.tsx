import './lib/tauriApi'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import { appStore } from './state/store'
import './styles.css'

void appStore.initialize()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
