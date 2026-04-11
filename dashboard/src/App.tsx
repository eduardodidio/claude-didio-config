import { Navigate, Routes, Route } from 'react-router-dom';
import { MainLayout } from '@/components/MainLayout';
import { Overview } from '@/views/Overview';
import { Features } from '@/views/Features';
import { Agents } from '@/views/Agents';
import EasterEggs from '@/views/EasterEggs';

export default function App() {
  return (
    <Routes>
      <Route element={<MainLayout />}>
        <Route index element={<Overview />} />
        <Route path="features" element={<Features />} />
        <Route path="agents" element={<Agents />} />
        <Route path="phrases" element={<EasterEggs />} />
        <Route path="easter-eggs" element={<Navigate to="/phrases" replace />} />
      </Route>
    </Routes>
  );
}
