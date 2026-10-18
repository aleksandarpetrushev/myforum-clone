export interface User {
  id: number;
  email: string;
  name: string;
  location: string | null;
}

export interface Session {
  token: string;
  user: User;
}

export interface Topic {
  id: number;
  name: string;
  slug: string;
  followed?: boolean;
}

export interface EventSummary {
  id: number;
  title: string;
  starts_at: string;
  ends_at: string;
  location: string;
  kind: string;
  capacity: number;
  reserved_spots: number;
  status: string;
  organization: { id: number; name: string };
  topics: Topic[];
  description?: string;
  speakers?: { id: number; name: string; title: string | null }[];
}

export interface Registration {
  id: number;
  status: string;
  event_id: number;
  event: { id: number; title: string; starts_at: string; location: string };
}

export interface NotificationItem {
  id: number;
  kind: string;
  title: string;
  body: string;
  read_at: string | null;
  created_at: string;
}

export interface ApiError {
  error: { code: string; message: string };
}
