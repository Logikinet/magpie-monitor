import { render } from 'preact';
import App from './app';
import './styles/tokens.css';
import './styles/base.css';

render(<App />, document.getElementById('app')!);
