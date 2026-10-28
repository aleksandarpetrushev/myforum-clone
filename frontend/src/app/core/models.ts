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
  visibility?: EventVisibility;
  allowed_organization_ids?: number[];
}

export type EventVisibility = 'public' | 'organization_restricted';

export interface Organization {
  id: number;
  name: string;
}

export interface CreateEventRequest {
  organization_id: number;
  title: string;
  description: string;
  location: string;
  kind: 'online' | 'in_person';
  capacity: number;
  starts_at: string;
  ends_at: string;
  status: 'draft' | 'published';
  visibility: EventVisibility;
  allowed_organization_ids: number[];
  topic_ids: number[];
}

export interface ValidationError {
  code: string;
  message: string;
  details?: Record<string, string[]>;
}

export interface Registration {
  id: number;
  status: string;
  event_id: number;
  event?: { id: number; title: string; starts_at: string; location: string } | null;
}

export interface NotificationItem {
  id: number;
  kind: string;
  title: string;
  body: string;
  read_at: string | null;
  created_at: string;
}

export interface NotificationPage {
  data: NotificationItem[];
  unread_count: number;
  next_cursor: string | null;
}

export interface NotificationPreferences {
  registration_confirmed_enabled: boolean;
  registration_cancelled_enabled: boolean;
}

export interface ApiError {
  error: { code: string; message: string };
}
