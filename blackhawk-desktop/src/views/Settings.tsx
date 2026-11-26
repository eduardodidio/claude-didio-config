import { Volume2, VolumeX, Rocket, Clock, Monitor } from 'lucide-react';
import { useSettings } from '@/hooks/useSettings';
import { Avatar } from '@/components/Avatar';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import { Skeleton } from '@/components/ui/skeleton';

export function Settings() {
  const { settings, loading, error, update, toggleSilent } = useSettings();

  if (loading) {
    return (
      <div className="p-3 space-y-3">
        <Skeleton className="h-24 w-full rounded-lg" />
        <Skeleton className="h-20 w-full rounded-lg" />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3 p-3">
      {error && (
        <div className="text-xs text-destructive bg-destructive/10 rounded-lg px-3 py-2">
          {error}
        </div>
      )}

      {/* Avatar & Identity */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">Identity</CardTitle>
        </CardHeader>
        <CardContent className="flex items-center gap-3">
          <Avatar
            src={settings.avatarPath || undefined}
            size="lg"
            className="didio-glow"
          />
          <div>
            <p className="text-sm font-semibold">Black Hawk Alpha</p>
            <p className="text-[10px] text-muted-foreground">Commander / Primary Agent</p>
          </div>
        </CardContent>
      </Card>

      {/* Notification Settings */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">Notifications</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <SettingToggle
            icon={settings.silentMode ? VolumeX : Volume2}
            label="Silent Mode"
            description="Suppress all desktop notifications"
            enabled={settings.silentMode}
            onToggle={toggleSilent}
          />
          <Separator />
          <SettingToggle
            icon={Volume2}
            label="Notification Sound"
            description="Play sound with notifications"
            enabled={settings.notificationSound}
            onToggle={() => update({ notificationSound: !settings.notificationSound })}
          />
        </CardContent>
      </Card>

      {/* Startup & Behavior */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">Behavior</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <SettingToggle
            icon={Rocket}
            label="Auto-Launch"
            description="Start Black Hawk with your system"
            enabled={settings.autoLaunch}
            onToggle={() => update({ autoLaunch: !settings.autoLaunch })}
          />
          <Separator />
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Clock className="h-4 w-4 text-muted-foreground" />
              <div>
                <p className="text-xs font-medium">Triage Interval</p>
                <p className="text-[10px] text-muted-foreground">
                  Auto-triage every {settings.triageIntervalMinutes}m
                </p>
              </div>
            </div>
            <div className="flex items-center gap-1">
              {[5, 15, 30, 60].map((val) => (
                <Button
                  key={val}
                  variant={settings.triageIntervalMinutes === val ? 'default' : 'ghost'}
                  size="sm"
                  className="h-6 text-[10px] px-2"
                  onClick={() => update({ triageIntervalMinutes: val })}
                >
                  {val}m
                </Button>
              ))}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Window */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">Window</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Monitor className="h-4 w-4 text-muted-foreground" />
              <div>
                <p className="text-xs font-medium">Position</p>
                <p className="text-[10px] text-muted-foreground">{settings.desktopPosition}</p>
              </div>
            </div>
            <div className="flex items-center gap-1 flex-wrap justify-end">
              {(['bottom-right', 'bottom-left', 'top-right', 'top-left'] as const).map((pos) => (
                <Button
                  key={pos}
                  variant={settings.desktopPosition === pos ? 'default' : 'ghost'}
                  size="sm"
                  className="h-6 text-[10px] px-2"
                  onClick={() => update({ desktopPosition: pos })}
                >
                  {pos.replace('-', ' ')}
                </Button>
              ))}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Version info */}
      <div className="text-center pt-2">
        <p className="text-[10px] text-muted-foreground">Black Hawk Desktop v0.1.0</p>
        <p className="text-[10px] text-muted-foreground">claude-didio-config</p>
      </div>
    </div>
  );
}

// ---- Internal toggle component ----

interface SettingToggleProps {
  icon: React.ElementType;
  label: string;
  description: string;
  enabled: boolean;
  onToggle: () => void;
}

function SettingToggle({ icon: Icon, label, description, enabled, onToggle }: SettingToggleProps) {
  return (
    <div className="flex items-center justify-between">
      <div className="flex items-center gap-2">
        <Icon className="h-4 w-4 text-muted-foreground" />
        <div>
          <p className="text-xs font-medium">{label}</p>
          <p className="text-[10px] text-muted-foreground">{description}</p>
        </div>
      </div>
      <button
        onClick={onToggle}
        className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${
          enabled ? 'bg-primary' : 'bg-muted'
        }`}
      >
        <span
          className={`inline-block h-3.5 w-3.5 transform rounded-full bg-background transition-transform ${
            enabled ? 'translate-x-4' : 'translate-x-0.5'
          }`}
        />
      </button>
    </div>
  );
}
