import {notification} from 'antd';

export type ApiResponse<T> = {
  success: boolean;
  data?: T;
  message?: string;
};

const isApiResponse = <T>(value: unknown): value is ApiResponse<T> => {
  return (
    typeof value === 'object' &&
    value !== null &&
    'success' in value &&
    typeof value.success === 'boolean'
  );
};

const readJsonResponse = async <T>(response: Response): Promise<ApiResponse<T>> => {
  const text = await response.text();

  if (!text.trim()) {
    return {success: false, message: 'Empty API response'};
  }

  try {
    const body: unknown = JSON.parse(text);
    return isApiResponse<T>(body) ? body : {success: false, message: 'Invalid API response'};
  } catch {
    return {success: false, message: 'Invalid JSON response'};
  }
};

export async function request<T>(url: string, init?: RequestInit): Promise<ApiResponse<T>> {
  let result: ApiResponse<T>;
  const headers = new Headers(init?.headers);

  if (init?.body && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  try {
    const response = await fetch(url, {
      method: 'POST',
      ...init,
      headers,
    });

    if (!response.ok) {
      let message = `Request failed (${response.status})`;
      const body = await readJsonResponse<unknown>(response);
      if (body.message) {
        message = body.message;
      }
      result = {success: false, message};
    } else {
      result = await readJsonResponse<T>(response);
    }
  } catch {
    result = {success: false, message: 'Network error'};
  }

  if (!result.success) {
    notification.error({message: 'Request Error', description: result.message});
  }

  return result;
}
